local Utils = require("scripts.utils")
local Core = require("scripts.core")
local Processor = {}

function Processor.apply_rich_resources_in_area(surface, area)
  if not surface or not surface.valid then return end
  if not global or not global.richResources then return end
  
  local multiplier = global.richResources.multiplier or 1
  if multiplier == 1 then return end

  local max_amount = 4294967295 
  
  for _, entity in pairs(surface.find_entities_filtered{area = area, type = "resource"}) do
    local entity_id = Utils.get_entity_identifier(entity)
    
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
        -- 未処理なので倍率を適用 (Coreロジックを使用)
        Core.apply_multiplier(entity, multiplier)
      end
    end
  end
end

return Processor
