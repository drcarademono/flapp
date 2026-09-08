from __future__ import annotations

import subprocess
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "plugins" / "jafl.koplugin"


class KOReaderPluginTests(unittest.TestCase):
    def test_required_plugin_files_exist(self) -> None:
        for relative in ("_meta.lua", "main.lua", "core/game.lua", "core/state.lua",
                         "core/save.lua", "content/xml.lua", "content/catalog.lua",
                         "ui/gameview.lua"):
            self.assertTrue((PLUGIN / relative).is_file(), relative)

    def test_plugin_does_not_embed_java_or_desktop_ui(self) -> None:
        source = "\n".join(path.read_text() for path in PLUGIN.rglob("*.lua"))
        self.assertNotIn("java -jar", source)
        self.assertNotIn("javax.swing", source)
        self.assertIn('require("ui/', source)

    def test_skill_check_branches_use_the_check_group(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("check.branches[#check.branches+1] = node", source)
        self.assertNotIn("check.data.branches[#check.data.branches+1] = node", source)

    def test_game_view_exposes_choices_and_map_inline(self) -> None:
        source = (PLUGIN / "ui" / "gameview.lua").read_text()
        self.assertIn("for i,a in ipairs(self.game.actions) do", source)
        self.assertIn('buttons_table=buttons', source)
        self.assertIn('text=_("Map")', source)
        self.assertIn('require("ui/widget/imageviewer")', source)
        self.assertIn('require("ui/renderimage")', source)
        self.assertIn('RenderImage:renderImageFile(map_path,false)', source)
        self.assertIn('image_disposable=true', source)
        self.assertNotIn('ImageViewer:new{image=map_path', source)
        self.assertNotIn('text=_("Choices")', source)
        self.assertNotIn('require("ui/widget/buttondialog")', source)

    def test_combat_matches_java_damage_and_resumes_section(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("math.max(0, roll - defence)", source)
        self.assertIn("local attack_dice=tonumber(a.attackdice) or 2", source)
        self.assertIn("local enemy_attacks=tonumber(a.attacks) or 1", source)
        self.assertIn("self.section_runner=coroutine.create", source)
        self.assertIn("self:resume_section()", source)
        self.assertIn("self:pause_section()", source)
        self.assertIn("running==self.section_runner", source)
        self.assertNotIn("local running,is_main=coroutine.running()", source)
        self.assertNotIn("self:value(a.damage or 1)", source)

    def test_combat_uses_parser_normalized_attribute_names(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        for attribute in ("playerdefence", "attackdice", "playerfirst", "predamage",
                          "staminalost", "abilitydamaged"):
            self.assertIn("a." + attribute, source)
        for attribute in ("playerDefence", "attackDice", "playerFirst", "preDamage",
                          "staminaLost", "abilityDamaged"):
            self.assertNotIn("a." + attribute, source)

    def test_loss_effects_support_java_recovery_semantics(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("if a.staminato then", source)
        self.assertIn('if (a.shards=="*" or a.gold=="*") and direction<0', source)

    def test_destinations_match_java_alive_and_dead_states(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("local function destination_matches_life_state", source)
        self.assertIn("(state.stamina<=0)==truth(attributes.dead,false)", source)
        self.assertNotIn("(self.state.stamina>0)==truth(a.dead,false)", source)

    def test_extended_java_game_systems_are_dispatched(self) -> None:
        game = (PLUGIN / "core" / "game.lua").read_text()
        state = (PLUGIN / "core" / "state.lua").read_text()
        for kind in ('action.kind=="random"', 'action.kind=="training"',
                     'action.kind=="return"', 'action.kind=="resurrection"',
                     'action.kind=="resurrect"', 'action.kind=="cache"'):
            self.assertIn(kind, game)
        self.assertIn("function Game:open_market", game)
        self.assertIn("function Game:apply_affliction", game)
        self.assertIn("local function range_matches", game)
        self.assertIn("local function pair_fight_nodes", game)
        self.assertIn("function State.remove_matching_items", state)
        for field in ("diseases = {}", "poisons = {}", "caches = {}", "history = {}"):
            self.assertIn(field, state)

    def test_content_validator(self) -> None:
        subprocess.run(["python3", "tools/validate-koreader-content.py"], cwd=ROOT, check=True)

    def test_built_archive_has_installable_layout(self) -> None:
        subprocess.run(["sh", "tools/package-koreader-plugin.sh"], cwd=ROOT, check=True)
        archive = ROOT / "dist" / "jafl.koplugin.zip"
        with zipfile.ZipFile(archive) as package:
            names = set(package.namelist())
            self.assertIn("jafl.koplugin/main.lua", names)
            self.assertIn("jafl.koplugin/_meta.lua", names)
            self.assertIn("jafl.koplugin/contentpack/book1/1.xml", names)
            self.assertIn("jafl.koplugin/contentpack/book6/book.ini", names)
            bad = package.testzip()
            self.assertIsNone(bad)


if __name__ == "__main__":
    unittest.main()
