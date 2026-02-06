local Core = require("scripts.core")
local Utils = require("scripts.utils")

local Debug = {}

function Debug.register()
  -- ゲーム内で /c remote.call("RichResourcesDebug", "コマンド名", 引数...) で呼び出せます
  remote.add_interface("RichResourcesDebug", {
    
    -- 選択中のエンティティに倍率を適用するテスト
    -- 使用例: /c remote.call("RichResourcesDebug", "apply", 10)
    apply = function(multiplier)
      local player = game.get_player(1)
      if not player or not player.selected then
        game.print("[Debug] エラー: エンティティを選択（マウスオーバー）してください。")
        return
      end
      
      local entity = player.selected
      if entity.type ~= "resource" then
        game.print("[Debug] エラー: 選択されたエンティティは資源(resource)ではありません。")
        return
      end

      local m = tonumber(multiplier) or 2.0
      game.print("[Debug] テスト適用開始: x" .. m .. " 対象: " .. entity.name .. " (現在量: " .. entity.amount .. ")")
      
      local result = Core.apply_multiplier(entity, m)
      
      if result then
        game.print("[Debug] 成功しました。変更後: " .. entity.amount)
        if entity.tags then
            -- serpentはFactorioに含まれるデバッグ用シリアライザです
            game.print("[Debug] Tags: " .. serpent.block(entity.tags))
        end
      else
        game.print("[Debug] 失敗しました（Core.apply_multiplierがfalseを返しました）。")
      end
    end,

    -- グローバル変数の状態確認
    -- 使用例: /c remote.call("RichResourcesDebug", "status")
    status = function()
        if global.richResources then
            game.print("=== RichResources Status ===")
            game.print("Generation: " .. tostring(global.richResources.generation))
            game.print("Multiplier: " .. tostring(global.richResources.multiplier))
            game.print("Maintenance Mode: " .. tostring(global.richResources.job_type == "maintenance"))
            
            local processed_count = 0
            if global.richResources.processed_entities then
                for _ in pairs(global.richResources.processed_entities) do processed_count = processed_count + 1 end
            end
            game.print("Processed Entities Cache: " .. processed_count)
            
            if global.richResources.apply_queue then
                game.print("Queue Length: " .. #global.richResources.apply_queue)
            else
                game.print("Queue: Inactive")
            end
        else
            game.print("global.richResources is nil")
        end
    end,

    -- 選択中のエンティティのタグをリセット（再適用テスト用）
    -- 使用例: /c remote.call("RichResourcesDebug", "reset_entity")
    reset_entity = function()
      local player = game.get_player(1)
      if not player or not player.selected then return end
      local entity = player.selected
      
      -- タグのリセット
      if entity.tags and (entity.tags.rich_resources_applied or entity.tags.rich_resources_gen) then
        local t = entity.tags
        t.rich_resources_applied = nil
        t.rich_resources_gen = nil
        entity.tags = t
        game.print("[Debug] タグ情報を消去しました。")
      else
        game.print("[Debug] リセット対象のタグはありませんでした。")
      end

      -- キャッシュ(processed_entities)からの削除
      if global.richResources and global.richResources.processed_entities then
        local entity_id = Utils.get_entity_identifier(entity)
        if entity_id and global.richResources.processed_entities[entity_id] then
            global.richResources.processed_entities[entity_id] = nil
            game.print("[Debug] 処理済みリスト(キャッシュ)から削除しました。")
        else
            game.print("[Debug] 処理済みリストには含まれていませんでした。")
        end
      end

      game.print("[Debug] リセット完了。再適用可能です。")
    end,

    -- 自動生成・検証テスト（統合版）
    -- 1. 現在地でテストを実行
    -- 2. 指定距離（デフォルト5000）へテレポートしてテストを実行
    -- 3. 元の場所へ帰還
    -- テスト結果は script-output/RichResources_test.log にも出力されます
    -- 使用例: /c remote.call("RichResourcesDebug", "autotest")
    autotest = function(target_distance)
      local player = game.get_player(1)
      if not player then return end
      local surface = player.surface
      local original_pos = player.position
      local dist = tonumber(target_distance) or 5000
      
      -- ログファイル初期化
      local log_file = "RichResources_test.log"
      
      -- ファイル書き込みヘルパー (Factorioのバージョン互換対応)
      local function write_to_disk(text, append)
          if helpers and helpers.write_file then
              -- Factorio 2.0+
              helpers.write_file(log_file, text, append)
          elseif game and game.write_file then
              -- Factorio 1.1 older
              game.write_file(log_file, text, append)
          end
      end

      write_to_disk("=== RichResources 統合テスト開始 ===\n", false)
      
      -- ログ出力用関数（チャットとファイル両方に出力）
      local function log(msg)
          game.print(msg)
          write_to_disk(msg .. "\n", true)
      end

      -- テストスイート実行関数
      local function run_test_suite(location_label)
          local current_pos = player.position
          log(string.format("--- [%s] テスト実行 (x=%.0f, y=%.0f) ---", location_label, current_pos.x, current_pos.y))

          local function run_case(case_name, offset_x, initial_amount, multiplier)
             local target_pos = {x = current_pos.x + offset_x, y = current_pos.y}
             
             -- チャンク生成を強制（エラー回避のため重要）
             surface.request_to_generate_chunks(target_pos, 0)
             surface.force_generate_chunk_requests()

             -- 埋め立て処理 (水場ならlandfillを敷く)
             local tile = surface.get_tile(target_pos)
             -- 注意: collides_with("water-tile") は環境によってエラーになるため、collision_maskを確認する
             local is_water = false
             if tile and tile.valid then
                 if tile.prototype.collision_mask and tile.prototype.collision_mask["water-tile"] then
                     is_water = true
                 elseif tile.name == "water" or tile.name == "deepwater" then
                     is_water = true
                 end
             end

             if is_water then
                 local tiles = {}
                 for dx = -1, 1 do
                     for dy = -1, 1 do
                        table.insert(tiles, {name="landfill", position={x=target_pos.x+dx, y=target_pos.y+dy}})
                     end
                 end
                 surface.set_tiles(tiles)
                 local fishes = surface.find_entities_filtered{area={{target_pos.x-1, target_pos.y-1}, {target_pos.x+1, target_pos.y+1}}, type="fish"}
                 for _, f in pairs(fishes) do f.destroy() end
                 log("[Debug] 水場を埋め立てました: x=" .. target_pos.x)
             end
             
             -- 既存エンティティ掃除
             local existing = surface.find_entities_filtered{position = target_pos, radius=1, type="resource"}
             for _, e in pairs(existing) do e.destroy() end
             
             -- 資源生成
             local entity = surface.create_entity{name = "iron-ore", position = target_pos, amount = initial_amount}
             if not entity then
                 log(string.format("[Skip] %s: 生成失敗 - 場所が無効か干渉があります", case_name))
                 return
             end

             -- 期待値計算
             local expected = math.floor(initial_amount * multiplier)
             local dist_bonus_msg = ""
             if settings.global["richresources-enable-distance-bonus"] and settings.global["richresources-enable-distance-bonus"].value then
                 local d_val = math.sqrt(target_pos.x^2 + target_pos.y^2)
                 local interval = settings.global["richresources-distance-interval"].value
                 local rate = settings.global["richresources-distance-rate"].value
                 if interval > 0 then
                     local bonus = math.floor(d_val / interval) * rate
                     expected = math.floor(initial_amount * multiplier * (1.0 + bonus))
                     dist_bonus_msg = string.format(" (距離: %.0f, ボーナス: +%.0f%%)", d_val, bonus * 100)
                 end
             end
             
             -- 実行と検証
             Core.apply_multiplier(entity, multiplier)
             local result = entity.amount
             if result == expected then
                 log(string.format("[PASS] %s: %d -> %d%s", case_name, initial_amount, result, dist_bonus_msg))
                 entity.destroy() 
             else
                 log(string.format("[FAIL] %s: %d -> %d (期待値: %d)%s", case_name, initial_amount, result, expected, dist_bonus_msg))
             end
          end
          
          -- 個別ケースのエラーハンドリング
          local function safe_run_case(name, off, init, mult)
              local status, err = pcall(function() run_case(name, off, init, mult) end)
              if not status then
                  log(string.format("[ERROR] %s: 実行時エラーが発生しました - %s", name, err))
              end
          end
          
          safe_run_case("通常ケース(x2)", 2, 1000, 2)
          safe_run_case("高倍率ケース(x10)", 4, 1000, 10)
          safe_run_case("少量ケース(x2)", 6, 10, 2)
      end

      -- 1. 現在地でテスト
      run_test_suite("現在地")

      -- 2. 遠方へ移動
      local tp_pos = {x = dist, y = 0}
      log("[Debug] 遠方地点へ移動してテストします... (" .. dist .. ")")
      
      -- 移動先の足場確保（チャンク強制生成）
      surface.request_to_generate_chunks(tp_pos, 1)
      surface.force_generate_chunk_requests()
      
      local tile = surface.get_tile(tp_pos)
      local is_water = false
      if tile and tile.valid then
          if tile.prototype.collision_mask and tile.prototype.collision_mask["water-tile"] then
              is_water = true
          elseif tile.name == "water" or tile.name == "deepwater" then
              is_water = true
          end
      end

      if is_water then
          surface.set_tiles({{name="landfill", position=tp_pos}})
      end
      player.teleport(tp_pos)

      -- 3. 遠方でテスト
      run_test_suite("遠方地点")

      -- 4. 帰還
      log("[Debug] 元の場所へ帰還します。")
      player.teleport(original_pos)
      log("=== 統合テスト終了 ===")
    end,

    -- 遠方にテレポートする (距離ボーナステスト用)
    -- 使用例: /c remote.call("RichResourcesDebug", "tp", 5000)
    tp = function(distance)
        local player = game.get_player(1)
        if not player then return end
        
        local d = tonumber(distance) or 1000
        -- X軸方向に移動 (Y=0)
        local target_pos = {x = d, y = 0}
        
        -- 安全な場所を探す (水没などを防ぐ)
        local safe_pos = player.surface.find_non_colliding_position("character", target_pos, 50, 1)
        
        if safe_pos then
            player.teleport(safe_pos)
            game.print("[Debug] 距離 " .. d .. " 地点へテレポートしました。")
            -- 周囲のチャンクを生成（テスト用）
            player.surface.request_to_generate_chunks(safe_pos, 2)
        else
            -- 見つからない場合は強制移動（ゴーストモード推奨）
            player.teleport(target_pos)
            game.print("[Debug] 指定座標へ強制テレポートしました（安全地帯が見つかりませんでした）。")
        end
    end
  })
end

return Debug
