local Utils = require("scripts.utils")
local Core = require("scripts.core")
local Worker = {}

local CHUNK_SIZE = 32
local CHUNKS_PER_TICK = 32

function Worker.process_apply_queue(event)
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
          local entity_id = Utils.get_entity_identifier(entity)
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
            -- Use Core logic for consistent application
            if Core.apply_multiplier(entity, multiplier) then
                global.richResources.apply_processed_count = (global.richResources.apply_processed_count or 0) + 1
            end
          end
        end
      end
    end
  end

  -- キューを全て処理し終えたら停止し、メッセージ表示
  if #queue == 0 then
    script.on_nth_tick(1, nil)
    
    local was_maintenance = (global.richResources.job_type == "maintenance")
    if not was_maintenance then
        global.richResources.existing_applied = true
    end
    
    global.richResources.job_type = nil
    global.richResources.job_multiplier = nil

    local count = global.richResources.apply_processed_count or 0
    pcall(function()
      game.print({"gui.rich-resources-applied-message"})
    end)
    
    -- Check pending jobs
    if global.richResources.pending_job then
        local job = global.richResources.pending_job
        global.richResources.pending_job = nil
        
        global.richResources.generation = job.generation
        global.richResources.job_type = job.type
        global.richResources.job_multiplier = job.multiplier
        global.richResources.existing_applied = false
        
        game.print("[RichResources] Starting queued task: " .. job.type .. " x" .. job.multiplier)
        Worker.start_apply_to_existing_resources()
    end
  end
end

function Worker.start_apply_to_existing_resources()
  if not global or not global.richResources then return false end
  if global.richResources.apply_queue and #global.richResources.apply_queue > 0 then return false end

  global.richResources.apply_queue = {}
  global.richResources.apply_processed_count = 0

  for _, surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
      table.insert(global.richResources.apply_queue, {surface_index = surface.index, x = chunk.x, y = chunk.y})
    end
  end

  script.on_nth_tick(1, Worker.process_apply_queue)
  return true
end

return Worker
