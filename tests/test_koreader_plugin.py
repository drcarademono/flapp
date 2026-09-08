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
        self.assertIn("for i=first,last do", source)
        self.assertIn("local a=self.game.actions[i]", source)
        self.assertIn('buttons_table=buttons', source)
        self.assertIn('text=_("Map")', source)
        self.assertIn('require("ui/widget/imageviewer")', source)
        self.assertIn('require("ui/renderimage")', source)
        self.assertIn('RenderImage:renderImageFile(map_path,false)', source)
        self.assertIn('image_disposable=true', source)
        self.assertNotIn('ImageViewer:new{image=map_path', source)
        self.assertNotIn('text=_("Choices")', source)
        self.assertNotIn('require("ui/widget/buttondialog")', source)
        self.assertIn("local BOOK_TEXT_SIZE=12", source)
        self.assertIn("text_font_size=BOOK_TEXT_SIZE", source)
        self.assertIn("font_bold=false", source)
        self.assertIn("text_size=BOOK_TEXT_SIZE", source)
        self.assertIn("local ACTIONS_PER_PAGE=6", source)
        self.assertIn("local page_count=math.max(1,math.ceil(action_count/ACTIONS_PER_PAGE))", source)
        self.assertIn('text=_("Previous")', source)
        self.assertIn('text=_("Next")', source)

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
        self.assertIn('local is_dead=state.profession~="" and state.stamina<=0', source)
        self.assertIn("return is_dead==truth(attributes.dead,false)", source)
        self.assertNotIn("(self.state.stamina>0)==truth(a.dead,false)", source)

    def test_new_game_profession_choices_are_not_treated_as_death_routes(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn('state.profession~=""', source)
        section = (ROOT / "book1" / "New.xml").read_text()
        for profession in ("Liana", "Andriel", "Chalor", "Marana", "Ignatius", "Astariel"):
            self.assertIn(f'<choice section="{profession}">', section)

    def test_new_game_selects_an_installed_starting_book(self) -> None:
        game = (PLUGIN / "core" / "game.lua").read_text()
        catalog = (PLUGIN / "content" / "catalog.lua").read_text()
        main = (PLUGIN / "main.lua").read_text()
        self.assertIn("function Game:choose_starting_book()", game)
        self.assertIn('action.kind=="startbook"', game)
        self.assertIn('self.state.section="New"', game)
        self.assertIn("function Catalog:installed_books()", catalog)
        self.assertIn('installed = exists(join(path, "New.xml"))', catalog)
        self.assertIn("new_game and game:choose_starting_book() or nil", main)

    def test_bundled_books_override_stale_external_content_setting(self) -> None:
        main = (PLUGIN / "main.lua").read_text()
        bundled = main.index('local bundled = plugin_dir .. "contentpack"')
        configured = main.index('local configured = G_reader_settings:readSetting("jafl_content_root")')
        self.assertLess(bundled, configured)
        self.assertIn('io.open(bundled .. "/books.ini", "rb")', main)

    def test_extended_java_game_systems_are_dispatched(self) -> None:
        game = (PLUGIN / "core" / "game.lua").read_text()
        state = (PLUGIN / "core" / "state.lua").read_text()
        for kind in ('action.kind=="random"', 'action.kind=="training"',
                     'action.kind=="return"', 'action.kind=="resurrection"',
                     'action.kind=="resurrect"', 'action.kind=="cache"'):
            self.assertIn(kind, game)
        self.assertIn("function Game:open_market", game)
        self.assertIn('self:add_action("Leave market","leave_market"', game)
        self.assertIn('action.kind=="leave_market"', game)
        self.assertIn("function Game:apply_affliction", game)
        self.assertIn("local function range_matches", game)
        self.assertIn("local function pair_fight_nodes", game)
        self.assertIn("function State.remove_matching_items", state)
        for field in ("diseases = {}", "poisons = {}", "caches = {}", "history = {}"):
            self.assertIn(field, state)

    def test_outcomes_dispatch_success_and_failure_transitions(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn('local default_var=has_check_branch and "*difficulty*" or "*random*"', source)
        self.assertIn("local value=self.state.variables[a.var or default_var]", source)
        self.assertIn('c.name=="success" and value~=nil and value>0', source)
        self.assertIn('c.name=="failure" and value~=nil and value<=0', source)
        section = (ROOT / "book1" / "257.xml").read_text()
        self.assertIn('<success section="630"/>', section)
        self.assertIn('<failure section="36"/>', section)

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
