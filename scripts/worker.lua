local Core = require("scripts.core")
local Worker = {}

local CHUNK_SIZE = 32
local CHUNKS_PER_TICK = 32

function Worker.process_apply_queue(event)
  -- storageが初期化されていない、またはキューが存在しない場合は即座に終了
  if not storage.richResources or not storage.richResources.apply_queue then
    return
  end
  
  local queue = storage.richResources.apply_queue
  if #queue == 0 then return end

  -- Refresh multiplier from settings every tick or batch to allow runtime updates
  local multiplier = storage.richResources.multiplier or 1
  local is_maintenance = (storage.richResources.job_type == "maintenance")

  if is_maintenance then
    multiplier = storage.richResources.job_multiplier or 1
  else
    if multiplier == 1 and not storage.richResources.job_type then
        -- Multiplier is 1, so no work needed. Clear queue.
        storage.richResources.apply_queue = {}
        storage.richResources.existing_applied = true
        
        if storage.richResources.pending_job then
            local job = storage.richResources.pending_job
            storage.richResources.pending_job = nil
            -- storage.richResources.generation = job.generation -- generation is usually managed elsewhere
            storage.richResources.job_type = job.type
            storage.richResources.job_multiplier = job.multiplier
            storage.richResources.existing_applied = false
            game.print("[RichResources] Starting queued task: " .. (job.type or "unknown") .. " x" .. (job.multiplier or 1))
            Worker.start_apply_to_existing_resources()
        end
        return
    end
  end

  local current_gen = storage.richResources.generation or 1
  storage.richResources.processed_chunks = storage.richResources.processed_chunks or {} -- Ensure it exists
  
  -- Process a batch of chunks
  -- 1ティックあたりの処理数を設定（高負荷防止）
  -- 以前は CHUNKS_PER_TICK (32) でしたが、より安全な 5 に変更を推奨されたのでそれに従う、
  -- あるいは変数で制御。ユーザー指定は local tasks_per_tick = 5
  -- 元のコードにある定数定義 CHUNKS_PER_TICK を活用したいが、ユーザーの指示は「5」
  local tasks_per_tick = 5 
  local to_process = math.min(tasks_per_tick, #queue)

  for i = 1, to_process do
    local job = table.remove(queue) -- Removes last element
    if job then
      local surface = game.get_surface(job.surface_index)
      if surface and surface.valid then
        local surface_idx = surface.index
        storage.richResources.processed_chunks[surface_idx] = storage.richResources.processed_chunks[surface_idx] or {}
        local chunk_id = job.x .. "_" .. job.y
        local chunk_gen = storage.richResources.processed_chunks[surface_idx][chunk_id] or 0

        local should_process = false
        if is_maintenance then
            -- 過去に処理されており、かつ今の世代より古い場合のみ追加適用
            if chunk_gen > 0 and chunk_gen < current_gen then
                should_process = true
            end
        else
            -- まだ今の世代で処理されていない場合
            if chunk_gen < current_gen then
                should_process = true
            end
        end

        if should_process then
            -- Worker.process_apply_queue 内の処理
            -- ここで Processor などを呼ぶ形にリファクタリングする提案もありましたが、
            -- 既存コードのロジックがここに展開されているのでそのまま維持しつつ、
            -- 安全かつ少しずつ実行するようにします。
            
            local area = {
              left_top = {x = job.x * CHUNK_SIZE, y = job.y * CHUNK_SIZE},
              right_bottom = {x = (job.x + 1) * CHUNK_SIZE, y = (job.y + 1) * CHUNK_SIZE}
            }
            
            -- 同期ズレ防止用のRNG生成
            local seed = 12345
            if surface.map_gen_settings and surface.map_gen_settings.seed then
                seed = surface.map_gen_settings.seed
            end
            local unique_seed = (seed + job.x * 0x1F1F + job.y * 0x7373) % 0x100000000
            local rng = game.create_random_generator(unique_seed)

            for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
              local pos = entity.position 
              -- Strict area check just in case, though find_entities_filtered usually handles it well enough for chunks
              if pos.x >= area.left_top.x and pos.x < area.right_bottom.x and
                 pos.y >= area.left_top.y and pos.y < area.right_bottom.y then
                 
                 if Core.apply_multiplier(entity, multiplier, rng) then
                     storage.richResources.apply_processed_count = (storage.richResources.apply_processed_count or 0) + 1
                 end
              end
            end
            
            -- Mark chunk as processed for this generation
            storage.richResources.processed_chunks[surface_idx][chunk_id] = current_gen
        end
      end
    end
  end

  if #queue == 0 then
    -- 修正: nil ではなく空のテーブルを代入する
    storage.richResources.apply_queue = {}
    -- storage.richResources.existing_applied = true -- Done in block below? No, let's keep logic here
    
    if not is_maintenance then
        storage.richResources.existing_applied = true
    end
    
    storage.richResources.job_type = nil
    storage.richResources.job_multiplier = nil
    
    game.print("[RichResources] Finished applying to existing chunks.")
    
    if storage.richResources.pending_job then
        local next_job = storage.richResources.pending_job
        storage.richResources.pending_job = nil
        -- storage.richResources.generation = next_job.generation
        storage.richResources.job_type = next_job.type
        storage.richResources.job_multiplier = next_job.multiplier
        storage.richResources.existing_applied = false  
        game.print("[RichResources] Starting next queued task: " .. tostring(next_job.type))
        Worker.start_apply_to_existing_resources()
    end
  end
end
      end
    end
  end

  if #queue == 0 then
    -- 修正: nil ではなく空のテーブルを代入する
    storage.richResources.apply_queue = {}
    storage.richResources.existing_applied = true
    game.print("[RichResources] Finished applying to existing chunks.")
    
    if storage.richResources.pending_job then
        local next_job = storage.richResources.pending_job
        storage.richResources.pending_job = nil
        -- storage.richResources.generation = next_job.generation
        storage.richResources.job_type = next_job.type
        storage.richResources.job_multiplier = next_job.multiplier
        storage.richResources.existing_applied = false  
        game.print("[RichResources] Starting next queued task: " .. tostring(next_job.type))
        Worker.start_apply_to_existing_resources()
    end
  end
end
              end
            end
            
            storage.richResources.processed_chunks[surface_idx][chunk_id] = current_gen
        end
      end
    end
  end

  if #queue == 0 then
    -- Queue finished.
    game.print("RichResources: Apply queue finished.")
    
    -- Assign empty table instead of nil to keep it safe for # checks
    storage.richResources.apply_queue = {}
    
    if not is_maintenance then
        storage.richResources.existing_applied = true
    end
    
    storage.richResources.job_type = nil
    storage.richResources.job_multiplier = nil

    pcall(function() game.print({"gui.rich-resources-applied-message"}) end)
    
    if storage.richResources.pending_job then
        local job = storage.richResources.pending_job
        storage.richResources.pending_job = nil
        storage.richResources.generation = job.generation
        storage.richResources.job_type = job.type
        storage.richResources.job_multiplier = job.multiplier
        storage.richResources.existing_applied = false
        
        game.print("[RichResources] Starting queued task: " .. job.type .. " x" .. job.multiplier)
        Worker.start_apply_to_existing_resources()
    end
  end
end

function Worker.start_apply_to_existing_resources()
  if not storage or not storage.richResources then return false end
  -- キューが空でない場合は、追加ジョブとして処理するかわかるべきだが、
  -- 簡易化のため既存キューがある場合は実行しない、あるいは再実行扱いにする
  if storage.richResources.apply_queue and #storage.richResources.apply_queue > 0 then 
      game.print("[RichResources] Job already running.")
      return false 
  end

  -- キューをローカル変数で作成 (修正案に従う)
  local queue = {}
  
  -- 全チャンクを列挙してキューに入れる
  -- 300x300チャンクでも9万件なので、Luaテーブルならメモリは大丈夫。
  -- 1ティックでループが回るかはPCスペック次第だが、これ以上の最適化は困難。
  for _, surface in pairs(game.surfaces) do
    if surface.valid then
        for chunk in surface.get_chunks() do
          table.insert(queue, {
              surface_index = surface.index,
              x = chunk.x, 
              y = chunk.y
          })
        end
    end
  end
  
  -- storage にキューを保存（nil ではなく空テーブルで初期化しておく）
  storage.richResources.apply_queue = queue
  storage.richResources.apply_processed_count = 0
  
  game.print("既存リソースの再計算を開始しました: " .. #queue .. " チャンク")
  return true
end

return Worker
