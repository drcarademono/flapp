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
                         "ui/gameview.lua", "TEXT_PARSING_AUDIT.md"):
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
        self.assertIn("local function menu_label(label)", source)
        self.assertIn('tostring(i)..". "..menu_label(a.label)', source)
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

    def test_not_conditions_can_return_false_for_installed_books(self) -> None:
        game = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn('if truth(a["not"],false) then return not ok end', game)
        self.assertNotIn('truth(a["not"], false) and not ok or ok', game)
        section = (ROOT / "book1" / "330.xml").read_text()
        self.assertIn('<if not="t" book="2">', section)
        self.assertIn('<goto book="2" section="217">', section)

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

    def test_ranged_outcome_creates_its_authored_destination(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn('elseif n=="outcome" then', source)
        self.assertIn("if a.section and destination_matches_life_state(self.state,a) then", source)
        self.assertIn('local label=plain(node)~="" and plain(node) or ("Turn to "..tostring(a.section))', source)
        self.assertIn('self:add_action(label,"goto",a)', source)
        section = (ROOT / "book2" / "101.xml").read_text()
        self.assertIn('<outcome range="10-12" section="499">A coven meeting</outcome>', section)

    def test_interaction_text_stays_in_authored_order(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("local function normalize_text(value)", source)
        self.assertIn(':gsub(" %- "," – "):gsub("%.%.%.","…")', source)
        self.assertIn("if label then self.text[#self.text+1]=label end", source)
        check_resume = source.index("if truth(a.force,true) then self:resume_section() end", source.index('if action.kind=="skillcheck"'))
        check_result = source.index('self.text[#self.text+1]="\\n\\n"..description', check_resume)
        self.assertLess(check_resume, check_result)
        random_start = source.index('elseif action.kind=="random"')
        random_resume = source.index("if truth(a.force,true) then self:resume_section() end", random_start)
        random_result = source.index('self.text[#self.text+1]="\\n\\nRolled "', random_resume)
        self.assertLess(random_resume, random_result)
        section = (ROOT / "book2" / "499.xml").read_text()
        self.assertIn("Make a MAGIC roll at a Difficulty of 11", section)
        self.assertIn("if (self.paragraph_depth or 0)>0 then", source)
        self.assertIn("self.pause_after_paragraph=true", source)
        self.assertIn("if self.paragraph_depth==0 and self.pause_after_paragraph then", source)
        self.assertIn("self.paragraph_depth=0; self.conditional_depth=0; self.hide_default_depth=0; self.deferred_block=false; self.pause_after_paragraph=false", source)
        self.assertIn("self.pause_before_outcomes=true", source)
        self.assertIn('elseif n=="outcomes" then\n        if self.pause_before_outcomes then', source)
        self.assertIn("function Game:resume_pending_check_children()", source)

    def test_inline_goto_renders_full_paragraph_without_executing_its_tail(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("function Game:render_node(node)", source)
        self.assertIn("self.deferred_block=true", source)
        self.assertIn("if self.deferred_block then\n            self:render_node(child)", source)
        self.assertIn('self.text[#self.text+1]=display_label', source)
        self.assertIn("if a.cache then available=(s.caches[a.cache] and s.caches[a.cache].shards) or 0 end", source)
        section = (ROOT / "book2" / "289.xml").read_text()
        self.assertNotIn('s.shards=0\n        return', source)
        self.assertNotIn('State.remove_matching_items(s,a)\n        return', source)
        self.assertIn('<lose item="*" shards="*">cross them off</lose>', section)
        self.assertIn('If not, the brigands <goto section="560">kill you</goto>.', section)

    def test_conditional_goto_renders_complete_branch_text(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn('local is_conditional=n=="if" or n=="elseif" or n=="else"', source)
        self.assertIn('self.deferred_block=true', source)
        self.assertIn('elseif type(child)=="string" and not child:match("%S") then', source)
        self.assertIn('self.text[#self.text+1]=display_label', source)
        section = (ROOT / "book2" / "409.xml").read_text()
        self.assertIn('If not, <goto section="353"/>.', section)

    def test_inactive_conditions_keep_their_java_document_text(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("function Game:goto_label(node)", source)
        self.assertIn('if n=="goto" then return self:goto_label(node) end', source)
        self.assertIn("if matched then self:walk(child,true) else self:render_node(child) end", source)
        self.assertIn("if not branch_taken then self:walk(child,true) else self:render_node(child) end", source)
        section = (ROOT / "book5" / "150.xml").read_text()
        self.assertIn('codeword="Diamond"', section)
        self.assertIn('codeword="Erebus"', section)
        self.assertIn('codeword="Evade"', section)

    def test_top_level_forced_goto_renders_trailing_text(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("function Game:is_new_sentence()", source)
        self.assertIn('(self:is_new_sentence() and "Turn to " or "turn to ")', source)
        self.assertIn('if n=="section" and self.deferred_block then', source)
        self.assertNotIn('else self:pause_section() end', source[source.index('elseif n=="goto" then'):source.index('elseif n=="set" then')])
        section = (ROOT / "book2" / "20.xml").read_text()
        self.assertIn('and <goto section="118"/>.', section)

    def test_java_empty_node_text_generators_are_ported(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("function Game:default_node_text(node)", source)
        for node in ("random", "difficulty", "rankcheck", "reroll", "training",
                     "lose", "tick", "image", "extrachoice", "field"):
            self.assertIn(f'n=="{node}"', source)
        self.assertIn('n=="item" or n=="weapon" or n=="armour" or n=="tool"', source)
        self.assertIn('node.name=="group" or node.name=="effect" or node.name=="tradeevent"', source)
        self.assertIn('self:add_action(label,"random",node)', source)
        self.assertIn('description=ea.ability:upper().." "', source)

    def test_random_roll_renders_trailing_text_before_pausing(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        random = source[source.index('elseif n=="random" then'):source.index('elseif n=="difficulty"')]
        self.assertIn("self.pause_after_paragraph=true", random)
        self.assertIn("self.pause_before_outcomes=true", random)
        self.assertNotIn("self:pause_section()", random)
        section = (ROOT / "book2" / "26.xml").read_text()
        self.assertIn('<random type="travel"/>:', section)

    def test_all_resumable_tags_preview_their_trailing_text(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        self.assertIn("function Game:preview_after(node)", source)
        self.assertIn("function Game:visible_text()", source)
        self.assertIn("node._parent,node._index=parent,index", source)
        self.assertIn("self.preview_text=nil", source[source.index("function Game:choose(index)"):])
        for marker in ('elseif n=="reroll"', 'elseif n=="fight"', 'elseif n=="return"',
                       'elseif n=="training"', 'elseif n=="market" or n=="trade"'):
            start = source.index(marker)
            self.assertIn("self:preview_after(node)", source[start:start + 500], marker)
        section = (ROOT / "book2" / "423.xml").read_text()
        self.assertIn('<training ability="thievery" dice="1"/>,', section)
        self.assertIn('Then <goto section="97"/>.', section)

    def test_interaction_results_follow_complete_authored_text(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        training = source[source.index('elseif action.kind=="training"'):source.index('elseif action.kind=="resurrection"')]
        self.assertLess(training.index("self:resume_section()"), training.index('"\\n\\nTraining roll: "'))
        fight = source[source.index('elseif action.kind=="fight"'):source.index('elseif action.kind=="market"')]
        self.assertLess(fight.index("self:resume_section()"), fight.index("self.text[#self.text+1]=combat_result"))

    def test_optional_check_results_do_not_leak_into_prose(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        branch = source[source.index('elseif n=="success" or n=="failure"'):source.index('elseif n=="outcomes"')]
        self.assertIn("if result==nil then", branch)
        self.assertIn("self:attach_check_branch(node)", branch)
        self.assertNotIn('or 0', branch)
        self.assertIn('self.state.variables["*difficulty*"]=nil', source)
        choose = source[source.index('elseif action.kind=="skillcheck"'):source.index('elseif action.kind=="random"')]
        self.assertIn('for _,branch in ipairs(group.branches or {}) do', choose)
        section = (ROOT / "book2" / "190.xml").read_text()
        self.assertIn('<difficulty ability="scouting" level="12" force="f">', section)
        self.assertIn('<failure section="213">Failed attempt to swim</failure>', section)

    def test_outcomes_keep_non_roll_fallback_choices(self) -> None:
        source = (PLUGIN / "core" / "game.lua").read_text()
        outcomes = source[source.index('elseif n=="outcomes"'):source.index('elseif n=="outcome" then')]
        self.assertIn("if value==nil then", outcomes)
        self.assertIn('child.name=="choice" then self:walk(child,true)', outcomes)
        self.assertIn("self:attach_check_branch(child)", outcomes)
        section = (ROOT / "book2" / "543.xml").read_text()
        self.assertIn('<if item="parchment">', section)
        self.assertIn('<difficulty ability="scouting" level="15">', section)
        self.assertIn('<choice section="518">No <b>parchment</b></choice>', section)

    def test_text_parsing_audit_tracks_platform_only_differences(self) -> None:
        audit = (PLUGIN / "TEXT_PARSING_AUDIT.md").read_text()
        self.assertIn("Java-compatible plain-text semantics now implemented", audit)
        self.assertIn("platform presentation differences", audit)

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
