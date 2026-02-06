local Utils = require("scripts.utils")
local Processor = require("scripts.processor")
local Worker = require("scripts.worker")
local Debug = require("scripts.debug")

-- デバッグ用インターフェース登録
Debug.register()

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
    local ok, err = pcall(function() Worker.start_apply_to_existing_resources() end)
    if not ok then
      log("RichResources: failed to start apply-to-existing on init: " .. tostring(err))
    end
  end
end)

script.on_load(function()
  -- Restore on_nth_tick handler if queue is active when loading save
  if global and global.richResources and global.richResources.apply_queue and #global.richResources.apply_queue > 0 then
      script.on_nth_tick(1, Worker.process_apply_queue)
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
    local ok, err = pcall(function() Worker.start_apply_to_existing_resources() end)
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
      Worker.start_apply_to_existing_resources()
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
          Worker.start_apply_to_existing_resources()
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
           
           Worker.start_apply_to_existing_resources()
       end

       -- Auto-reset switch
       settings.global["richresources-apply-maintenance"] = {value = false}
    end
  end
end)

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
          Processor.apply_rich_resources_in_area(item.surface, item.area)
       end
       table.remove(queue, i)
    end
  end
end)
