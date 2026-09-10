-- Behavioral expectations transcribed from ExecutableRunner, RandomNode,
-- DifficultyNode, and FightNode.RoundNode in the Java reference.
return {
    forced_random={
        fixture="forced_random.xml",
        before={marker=1,action="random"},
        restored={marker=1,action="random"},
        after={marker=2,roll=4},
    },
    blocking_combat_hook={
        fixture="combat_hook.xml",
        blocked_action="skillcheck",
        frame_kind="combat_hook",
        frame_phase="round_hook",
        completed_action="combat_continue",
        resumed_action="combat_attack",
    },
}
