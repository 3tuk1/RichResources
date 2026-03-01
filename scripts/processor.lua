local Core = require("scripts.core")
local Processor = {}

function Processor.apply_rich_resources_in_area(surface, area, rng)
  if not surface or not surface.valid then return end
  if not storage or not storage.richResources then return end
  
  local multiplier = storage.richResources.multiplier or 1
  if multiplier == 1 then return end

  local surface_idx = surface.index
  local cx = math.floor(area.left_top.x / 32)
  local cy = math.floor(area.left_top.y / 32)
  local chunk_id = cx .. "_" .. cy
  
  storage.richResources.processed_chunks = storage.richResources.processed_chunks or {}
  storage.richResources.processed_chunks[surface_idx] = storage.richResources.processed_chunks[surface_idx] or {}
  
  local current_gen = storage.richResources.generation or 1
  local chunk_gen = storage.richResources.processed_chunks[surface_idx][chunk_id] or 0
  
  if chunk_gen >= current_gen then return end -- この世代で既に処理済み

  for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
    local pos = entity.position
    -- エンティティの中心が厳密にチャンク内にある場合のみ処理（境界線での重複処理を防止）
    if pos.x >= area.left_top.x and pos.x < area.right_bottom.x and
       pos.y >= area.left_top.y and pos.y < area.right_bottom.y then
       
       Core.apply_multiplier(entity, multiplier, rng)
    end
  end
  
  -- チャンクを処理済みとしてマーク
  storage.richResources.processed_chunks[surface_idx][chunk_id] = current_gen
end

return Processor
