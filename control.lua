local Utils = require("scripts.utils")
local Processor = require("scripts.processor")
local Worker = require("scripts.worker")
local Debug = require("scripts.debug")

Debug.register()

script.on_init(function()
  -- storage is provided by the game engine in 2.0
  storage.richResources = storage.richResources or {}
  storage.richResources.apply_queue = {} -- 初期値は空テーブル
  storage.richResources.multiplier = settings.global["rich-resources-multiplier"].value
  storage.richResources.processed_chunks = {} 
  storage.richResources.delayed_chunks = {}
  storage.richResources.existing_applied = false
  storage.richResources.generation = 1

  -- 既存リソースへの適用を開始
  local apply_existing_setting = (settings.global and settings.global["richresources-apply-to-existing-ores"]) and settings.global["richresources-apply-to-existing-ores"].value or false
  if apply_existing_setting then
      Worker.start_apply_to_existing_resources()
  end
end)

script.on_load(function()
  -- Unconditional registration to prevent desyncs as per recommendation
  script.on_nth_tick(1, Worker.process_apply_queue)
end)

script.on_configuration_changed(function()
  -- storage is provided by the game engine in 2.0
  if not storage.richResources then storage.richResources = {} end
  
  storage.richResources.multiplier = settings.global["rich-resources-multiplier"].value
  
  -- セーブデータ肥大化の原因だった旧キャッシュを完全に削除
  if storage.richResources.processed_entities then
      storage.richResources.processed_entities = nil
  end
  if not storage.richResources.processed_chunks then
      storage.richResources.processed_chunks = {}
  end
  if not storage.richResources.delayed_chunks then storage.richResources.delayed_chunks = {} end
  if not storage.richResources.generation then storage.richResources.generation = 1 end

  local apply_existing_setting = (settings.global and settings.global["richresources-apply-to-existing-ores"]) and settings.global["richresources-apply-to-existing-ores"].value or false
  if apply_existing_setting and not storage.richResources.existing_applied then
    pcall(function() Worker.start_apply_to_existing_resources() end)
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  -- storageが未初期化の場合は何もしない
  if not storage or not storage.richResources then return end
  
  if event.setting == "rich-resources-multiplier" then
    storage.richResources.multiplier = settings.global["rich-resources-multiplier"].value
    game.print("[RichResources] Multiplier updated to: " .. storage.richResources.multiplier)

  elseif event.setting == "richresources-apply-to-existing-ores" then
    if settings.global["richresources-apply-to-existing-ores"].value then
      Worker.start_apply_to_existing_resources()
    else
      -- 停止時はキューをクリアする
      storage.richResources.apply_queue = {}
      storage.richResources.pending_job = nil 
      storage.richResources.job_type = nil
      game.print("[RichResources] Stops applying to existing ores.")
    end

  elseif event.setting == "richresources-reset-processed-list" then
    storage.richResources.generation = (storage.richResources.generation or 1) + 1
    storage.richResources.processed_chunks = {} 
    game.print("[RichResources] Processed chunks list reset. Generation: " .. storage.richResources.generation)
    if settings.global["richresources-apply-to-existing-ores"].value then
       Worker.start_apply_to_existing_resources()
    end

  elseif event.setting == "richresources-apply-maintenance" then
    local maint_mult = settings.global["rich-resources-maintenance-multiplier"].value
    game.print("[RichResources] Queueing maintenance task (x" .. maint_mult .. ")...")

    local job_params = {
       type = "maintenance",
       multiplier = maint_mult,
       generation = (storage.richResources.generation or 1) + 1
    }
    
    if storage.richResources.apply_queue and #storage.richResources.apply_queue > 0 then
        storage.richResources.pending_job = job_params
    else
        storage.richResources.generation = job_params.generation
        storage.richResources.job_type = job_params.type
        storage.richResources.job_multiplier = job_params.multiplier
        storage.richResources.existing_applied = false
        Worker.start_apply_to_existing_resources()
    end
  end
end)

script.on_event(defines.events.on_chunk_generated, function(event)
  if not storage or not storage.richResources then return end
  local multiplier = storage.richResources.multiplier
  if not multiplier or multiplier == 1 then return end
  if not storage.richResources.delayed_chunks then storage.richResources.delayed_chunks = {} end
  
  local safe_area = {
    left_top = {x = event.area.left_top.x, y = event.area.left_top.y},
    right_bottom = {x = event.area.right_bottom.x, y = event.area.right_bottom.y}
  }
  table.insert(storage.richResources.delayed_chunks, {
    surface_index = event.surface.index,
    area = safe_area,
    tick = event.tick
  })
end)

script.on_event(defines.events.on_tick, function(event)
  if not storage or not storage.richResources then return end
  local queue = storage.richResources.delayed_chunks
  if not queue or #queue == 0 then return end
  
  for i = #queue, 1, -1 do
    local item = queue[i]
    if item.tick < event.tick then
       local surface = game.surfaces[item.surface_index]
       if surface and surface.valid then
          local seed = 12345
          if surface.map_gen_settings and surface.map_gen_settings.seed then
              seed = surface.map_gen_settings.seed
          end
          local unique_seed = (seed + item.area.left_top.x * 0x1F1F + item.area.left_top.y * 0x7373) % 0x100000000
          local rng = game.create_random_generator(unique_seed)
          
          Processor.apply_rich_resources_in_area(surface, item.area, rng)
       end
       table.remove(queue, i)
    end
  end
end)
