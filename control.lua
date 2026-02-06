--[[ イベントハンドラの登録 ]]--

-- ゲーム/MODの初期化時 (新しいセーブデータで最初の一回だけ呼ばれる)
script.on_init(function()
  -- globalテーブルを確実に初期化
  global = global or {}
  global.richResources = {}
  global.richResources.multiplier = settings.global["rich-resources-multiplier"].value
  global.richResources.processed_entities = {} -- 処理済みエンティティのID管理
  global.richResources.delayed_chunks = {} -- 遅延処理用キュー
  global.richResources.existing_applied = global.richResources.existing_applied or false
  global.richResources.apply_queue = nil
  global.richResources.generation = 1

  -- 起動時設定が有効なら既存資源への適用を開始
  local apply_existing_setting = (settings.global and settings.global["richresources-apply-to-existing-ores"]) and settings.global["richresources-apply-to-existing-ores"].value or false
  if apply_existing_setting and not global.richResources.existing_applied then
    local ok, err = pcall(function() start_apply_to_existing_resources() end)
    if not ok then
      log("RichResources: failed to start apply-to-existing on init: " .. tostring(err))
    end
  end
end)

-- MOD構成変更時 (MODアップデート等)
script.on_configuration_changed(function()
  -- globalテーブルの存在チェックと初期化
  global = global or {}
  if not global.richResources then
    global.richResources = {}
    global.richResources.multiplier = settings.global["rich-resources-multiplier"].value
    global.richResources.processed_entities = {} -- 初期化
  end
  
  -- 倍率設定の更新（startup設定になったため毎回読み込む）
  global.richResources.multiplier = settings.global["rich-resources-multiplier"].value
  
  -- 処理済みエンティティリストが存在しない場合は初期化
  if not global.richResources.processed_entities then
    global.richResources.processed_entities = {}
  end
  if not global.richResources.delayed_chunks then
    global.richResources.delayed_chunks = {}
  end
  if not global.richResources.generation then
    global.richResources.generation = 1
  end
  global.richResources.existing_applied = global.richResources.existing_applied or false
  global.richResources.apply_queue = global.richResources.apply_queue -- preserve if mid-run
  
  -- 古いバージョンからのデータ移行処理
  if global.rich_resources_multiplier then
    global.richResources.multiplier = global.rich_resources_multiplier
    global.rich_resources_multiplier = nil
  end

  -- 起動時設定が有効なら既存資源への適用を開始（未実施の場合のみ）
  local apply_existing_setting = (settings.global and settings.global["richresources-apply-to-existing-ores"]) and settings.global["richresources-apply-to-existing-ores"].value or false
  if apply_existing_setting and not global.richResources.existing_applied then
    local ok, err = pcall(function() start_apply_to_existing_resources() end)
    if not ok then
      log("RichResources: failed to start apply-to-existing on configuration change: " .. tostring(err))
    end
  end
end)

-- 設定変更時（実行時）
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not global.richResources then return end
  
  if event.setting == "rich-resources-multiplier" then
    global.richResources.multiplier = settings.global["rich-resources-multiplier"].value
  elseif event.setting == "richresources-apply-to-existing-ores" then
    local enabled = settings.global["richresources-apply-to-existing-ores"].value
    if enabled then
      start_apply_to_existing_resources()
    else
      -- settings turned off, stop queue if running
      if global.richResources.apply_queue then
        global.richResources.apply_queue = nil
        script.on_nth_tick(1, nil)
        game.print("RichResources: Existing ore application stopped.")
      end
    end
  elseif event.setting == "richresources-reset-processed-list" then
    if settings.global["richresources-reset-processed-list"].value then
       -- Generation Increment Reset Strategy
       global.richResources.generation = (global.richResources.generation or 1) + 1
       global.richResources.processed_entities = {}
       game.print("[RichResources] Processed state reset. Generation: " .. global.richResources.generation)

       -- If auto-apply is ON, restart it
       if settings.global["richresources-apply-to-existing-ores"].value then
          global.richResources.existing_applied = false
          start_apply_to_existing_resources()
          game.print("[RichResources] Re-applying to existing resources...")
       end

       -- Auto-reset the toggle switch to false
       settings.global["richresources-reset-processed-list"] = {value = false}
    end
  elseif event.setting == "richresources-apply-maintenance" then
    if settings.global["richresources-apply-maintenance"].value then
       -- Maintenance Mode: Apply secondary multiplier to ALREADY PROCESSED entities
       local maint_mult = settings.global["rich-resources-maintenance-multiplier"].value
       game.print("[RichResources] Applying maintenance multiplier x" .. maint_mult .. " to processed ores...")

       -- Set job mode and parameters
       local job_params = {
          type = "maintenance",
          multiplier = maint_mult,
          generation = (global.richResources.generation or 1) + 1
       }
       
       -- Check if queue is running
       if global.richResources.apply_queue and #global.richResources.apply_queue > 0 then
           game.print("[RichResources] Task queued. Maintenance will start after current task completes.")
           global.richResources.pending_job = job_params
       else
           -- Start immediately
           global.richResources.generation = job_params.generation
           global.richResources.job_type = job_params.type
           global.richResources.job_multiplier = job_params.multiplier
           global.richResources.existing_applied = false
           
           start_apply_to_existing_resources()
       end

       -- Auto-reset switch
       settings.global["richresources-apply-maintenance"] = {value = false}
    end
  end
end)

-- Resource entities usually don't have unit_number, use position based ID
local function get_entity_identifier(entity)
  if entity.unit_number then return entity.unit_number end
  if entity.valid and entity.position then
    return string.format("%d_%.2f_%.2f", entity.surface.index, entity.position.x, entity.position.y)
  end
  return nil
end

-- チャンク生成時の処理 
-- 共通処理関数: 指定エリア内の資源に倍率を適用
local function apply_rich_resources_in_area(surface, area)
  if not surface or not surface.valid then return end
  if not global or not global.richResources then return end
  
  local multiplier = global.richResources.multiplier or 1
  if multiplier == 1 then return end

  local max_amount = 4294967295 
  
  for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
    local entity_id = get_entity_identifier(entity)
    
    -- 処理済みかチェック
    if entity_id and global.richResources.processed_entities[entity_id] then
      -- 既に処理済み、スキップ
    else
      -- pcallを使ってtagsへのアクセスを安全に行う
      local success, tags = pcall(function() return entity.tags end)
      
      local already = false
      if success and tags then
         local current_gen = global.richResources.generation or 1
         local entity_gen = tags.rich_resources_gen
         -- Old tag compatibility
         if not entity_gen and tags.rich_resources_applied then
            entity_gen = 1
         end
         
         if entity_gen and entity_gen >= current_gen then
            already = true
         end
      end

      if already then
        -- tagsで既に処理済みが確認できる場合
        if entity_id then
          global.richResources.processed_entities[entity_id] = true
        end
      else
        -- 未処理なので倍率を適用
        local new_amount = 0
        if entity.prototype.infinite_resource then
            -- Infinite resources: Ensure min base
            local min_base = settings.global["rich-resources-infinite-min-base"].value
            local base = entity.amount
            if base < min_base then base = min_base end
            new_amount = math.floor(base * multiplier)
        else
            -- Finite resources
            local base = entity.amount
            if base < 1 then base = 1 end
            new_amount = math.floor(base * multiplier)
        end

        if new_amount < 1 then new_amount = 1 end
        entity.amount = math.min(new_amount, max_amount)
        
        -- 処理済みマークを付ける
        if entity_id then
          global.richResources.processed_entities[entity_id] = true
        end
        
        -- tagsが利用可能な場合のみ設定
        if success then
          pcall(function() 
            local t = entity.tags or {}
            t.rich_resources_applied = true
            t.rich_resources_gen = global.richResources.generation or 1
            entity.tags = t
          end)
        end
      end
    end
  end
end

-- チャンク生成時の処理 (遅延実行登録)
script.on_event(defines.events.on_chunk_generated, function(event)
  if not global or not global.richResources then return end -- 安全装置
  local multiplier = global.richResources.multiplier
  if not multiplier or multiplier == 1 then return end
  
  if not global.richResources.delayed_chunks then global.richResources.delayed_chunks = {} end
  table.insert(global.richResources.delayed_chunks, {
    surface = event.surface,
    area = event.area,
    tick = event.tick
  })
end)

-- 毎Tick処理（遅延キュー消化）
script.on_event(defines.events.on_tick, function(event)
  if not global or not global.richResources then return end
  local queue = global.richResources.delayed_chunks
  if not queue or #queue == 0 then return end
  
  for i = #queue, 1, -1 do
    local item = queue[i]
    -- 1 Tick以上経過しているか確認 (他MODの生成完了待ち)
    if item.tick < event.tick then
       if item.surface and item.surface.valid then
          apply_rich_resources_in_area(item.surface, item.area)
       end
       table.remove(queue, i)
    end
  end
end)

-- 既存の資源へ適用するためのバッチ処理実装 ------------------------------
local CHUNK_SIZE = 32
local CHUNKS_PER_TICK = 32 -- 1tickあたりに処理するチャンク数（負荷対策）

-- 前方宣言
local process_apply_queue

-- 既存資源への適用を開始
function start_apply_to_existing_resources()
  if not global or not global.richResources then return false end
  -- 既にキューが存在する場合は何もしない
  if global.richResources.apply_queue and #global.richResources.apply_queue > 0 then return false end

  global.richResources.apply_queue = {}
  global.richResources.apply_processed_count = 0

  -- 全サーフェスの全チャンクをキューへ投入
  for _, surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
      table.insert(global.richResources.apply_queue, {surface_index = surface.index, x = chunk.x, y = chunk.y})
    end
  end

  -- Ntickごとの処理を開始
  script.on_nth_tick(1, process_apply_queue)
  return true
end

-- 1tickごとにキューから一定数のチャンクを処理
process_apply_queue = function(event)
  if not global or not global.richResources or not global.richResources.apply_queue then
    -- 何らかの理由で状態が消えていたら停止
    script.on_nth_tick(1, nil)
    return
  end

  local queue = global.richResources.apply_queue
  local multiplier = global.richResources.multiplier or 1
  -- Maintenance override
  if global.richResources.job_type == "maintenance" then
    multiplier = global.richResources.job_multiplier or 1
  else
    if multiplier == 1 then
        -- Normal mode with 1x -> skip
        script.on_nth_tick(1, nil)
        global.richResources.apply_queue = nil
        global.richResources.existing_applied = true
        return
    end
  end

  local max_amount = 4294967295
  local to_process = math.min(CHUNKS_PER_TICK, #queue)

  for i = 1, to_process do
    local job = table.remove(queue) -- 後方から取り出し（高速）
    if job then
      local surface = game.surfaces[job.surface_index]
      if surface and surface.valid then
        local area = {
          left_top = {x = job.x * CHUNK_SIZE, y = job.y * CHUNK_SIZE},
          right_bottom = {x = (job.x + 1) * CHUNK_SIZE, y = (job.y + 1) * CHUNK_SIZE}
        }
        for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
          local entity_id = get_entity_identifier(entity)
          local success, tags = pcall(function() return entity.tags end)

          local should_apply = false
          
          -- Check Logic depends on Mode
          if global.richResources.job_type == "maintenance" then
              -- MAINTENANCE MODE: Apply ONLY if previously processed
              local was_processed = false
              
              -- Check ID cache
              if entity_id and global.richResources.processed_entities[entity_id] then
                  was_processed = true
              end
              -- Check tags
              if success and tags and tags.rich_resources_applied then
                  was_processed = true
              end
              
              if was_processed then
                  local current_gen = global.richResources.generation or 1
                  local entity_gen = 0
                  if success and tags and tags.rich_resources_gen then
                      entity_gen = tags.rich_resources_gen
                  end
                  
                  if entity_gen < current_gen then
                      should_apply = true
                  end
              end
          else
              -- NORMAL MODE: Apply if NOT processed
              local already = false
              if entity_id and global.richResources.processed_entities[entity_id] then
                 already = true
              elseif success and tags then
                   local current_gen = global.richResources.generation or 1
                   local entity_gen = tags.rich_resources_gen
                   -- Old tag compatibility
                   if not entity_gen and tags.rich_resources_applied then
                      entity_gen = 1
                   end
                   
                   if entity_gen and entity_gen >= current_gen then
                      already = true
                   end
              end
              if not already then should_apply = true end
          end

          if should_apply then
            local new_amount = 0
            
            if entity.prototype.infinite_resource then
                -- Infinite resources (Oil): Ensure minimum base amount from settings
                local min_base = settings.global["rich-resources-infinite-min-base"].value
                local base = entity.amount
                if base < min_base then base = min_base end
                new_amount = math.floor(base * multiplier)
            else
                -- Finite resources: Ensure at least 1 before multiplier
                local base = entity.amount
                if base < 1 then base = 1 end
                new_amount = math.floor(base * multiplier)
            end

            if new_amount < 1 then new_amount = 1 end
            entity.amount = math.min(new_amount, max_amount)

            if entity_id then
              global.richResources.processed_entities[entity_id] = true
            end

            if success then
              pcall(function()
                local t = entity.tags or {}
                t.rich_resources_applied = true
                t.rich_resources_gen = global.richResources.generation or 1
                entity.tags = t
              end)
            end

            global.richResources.apply_processed_count = (global.richResources.apply_processed_count or 0) + 1
          end
        end
      end
    end
  end

  -- キューを全て処理し終えたら停止し、メッセージ表示
  if #queue == 0 then
    script.on_nth_tick(1, nil)
    
    -- If it was maintenance, we don't necessarily mark 'existing_applied' as true or false for global state
    -- but usually 'existing_applied' flag is for the auto-runner on startup.
    local was_maintenance = (global.richResources.job_type == "maintenance")
    if not was_maintenance then
        global.richResources.existing_applied = true
    end
    
    -- Clear job type
    global.richResources.job_type = nil
    global.richResources.job_multiplier = nil

    local count = global.richResources.apply_processed_count or 0
    -- ローカライズ済みのGUIキーを使って通知（game.valid は存在しないため直接呼ぶ）
    pcall(function()
      game.print({"gui.rich-resources-applied-message", tostring(count)})
    end)
    
    -- Check pending jobs
    if global.richResources.pending_job then
        local job = global.richResources.pending_job
        global.richResources.pending_job = nil
        
        -- Setup and start pending job
        global.richResources.generation = job.generation
        global.richResources.job_type = job.type
        global.richResources.job_multiplier = job.multiplier
        global.richResources.existing_applied = false
        
        game.print("[RichResources] Starting queued task: " .. job.type .. " x" .. job.multiplier)
        start_apply_to_existing_resources()
    end
  end
end