/// Real Metal HUD lines from the M2 spike (Rain World, 2026-10-26 and 10-29), as `log stream --style compact
/// --predicate 'eventMessage CONTAINS "metal-HUD"'` writes them with MTL_HUD_ENABLED=1 MTL_HUD_LOG_ENABLED=1.
/// The first field is the game's running frame count, sampled about every 0.41 s; the per-frame intervals are
/// `<private>` in the system log. Every sample appears twice, once from libMTLHud.dylib and once from
/// com.apple.metal.hud:Logging, so a parser counts one of them only. See docs/m2-spike.md.
enum HUDLogFixtures {
    /// D3DMetal: the stream's two header lines, the first sample (both copies), then 20 Logging samples at the menu.
    /// 2638 - 1707 frames over 20:05:55.667 - 20:05:47.909 = 7.758 s is 120.0 fps.
    static let d3dmetal = """
    Filtering the log data using "composedMessage CONTAINS "metal-HUD""
    Timestamp               Ty Process[PID:TID]
    2026-10-26 20:05:32.009 Df wine[74907:263582a] (libMTLHud.dylib) metal-HUD: 53,562.67,938.37<private>
    2026-10-26 20:05:32.009 Df wine[74907:263582a] [com.apple.metal.hud:Logging] metal-HUD: 53,562.67,938.37<private>
    2026-10-26 20:05:47.909 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 1707,565.88,1557.19<private>
    2026-10-26 20:05:48.317 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 1756,565.88,1557.19<private>
    2026-10-26 20:05:48.725 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 1805,565.88,1557.19<private>
    2026-10-26 20:05:49.134 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 1854,565.88,1557.19<private>
    2026-10-26 20:05:49.542 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 1903,565.88,1557.19<private>
    2026-10-26 20:05:49.950 Df wine[74907:26359d3] [com.apple.metal.hud:Logging] metal-HUD: 1952,565.88,1557.41<private>
    2026-10-26 20:05:50.359 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 2001,565.88,1557.41<private>
    2026-10-26 20:05:50.767 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 2050,565.88,1557.41<private>
    2026-10-26 20:05:51.175 Df wine[74907:2635999] [com.apple.metal.hud:Logging] metal-HUD: 2099,565.88,1557.41<private>
    2026-10-26 20:05:51.584 Df wine[74907:26359d2] [com.apple.metal.hud:Logging] metal-HUD: 2148,565.88,1557.41<private>
    2026-10-26 20:05:51.992 Df wine[74907:2635999] [com.apple.metal.hud:Logging] metal-HUD: 2197,565.88,1557.41<private>
    2026-10-26 20:05:52.400 Df wine[74907:263583a] [com.apple.metal.hud:Logging] metal-HUD: 2246,565.88,1557.41<private>
    2026-10-26 20:05:52.809 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 2295,565.88,1557.41<private>
    2026-10-26 20:05:53.217 Df wine[74907:2635829] [com.apple.metal.hud:Logging] metal-HUD: 2344,565.88,1557.43<private>
    2026-10-26 20:05:53.625 Df wine[74907:263583a] [com.apple.metal.hud:Logging] metal-HUD: 2393,565.88,1557.43<private>
    2026-10-26 20:05:54.034 Df wine[74907:263599a] [com.apple.metal.hud:Logging] metal-HUD: 2442,565.88,1557.43<private>
    2026-10-26 20:05:54.442 Df wine[74907:26359d3] [com.apple.metal.hud:Logging] metal-HUD: 2491,565.88,1557.43<private>
    2026-10-26 20:05:54.850 Df wine[74907:2635829] [com.apple.metal.hud:Logging] metal-HUD: 2540,565.88,1557.43<private>
    2026-10-26 20:05:55.259 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 2589,565.88,1557.43<private>
    2026-10-26 20:05:55.667 Df wine[74907:26359ce] [com.apple.metal.hud:Logging] metal-HUD: 2638,565.88,1557.43<private>
    """

    /// DXVK over MoltenVK, 10 Logging samples at the menu.
    /// 6112 - 5671 frames over 15:35:34.180 - 15:35:30.505 = 3.675 s is 120.0 fps.
    static let dxvk = """
    2026-10-29 15:35:30.505 Df wine[81300:28c83ec] [com.apple.metal.hud:Logging] metal-HUD: 5671,619.25,2046.06<private>
    2026-10-29 15:35:30.913 Df wine[81300:28c82f5] [com.apple.metal.hud:Logging] metal-HUD: 5720,619.25,2046.06<private>
    2026-10-29 15:35:31.322 Df wine[81300:28c82f5] [com.apple.metal.hud:Logging] metal-HUD: 5769,619.25,2046.06<private>
    2026-10-29 15:35:31.730 Df wine[81300:28c82a2] [com.apple.metal.hud:Logging] metal-HUD: 5818,619.25,2046.06<private>
    2026-10-29 15:35:32.138 Df wine[81300:28c8286] [com.apple.metal.hud:Logging] metal-HUD: 5867,619.25,2046.16<private>
    2026-10-29 15:35:32.547 Df wine[81300:28c82a3] [com.apple.metal.hud:Logging] metal-HUD: 5916,619.25,2046.16<private>
    2026-10-29 15:35:32.955 Df wine[81300:28c8286] [com.apple.metal.hud:Logging] metal-HUD: 5965,619.25,2046.16<private>
    2026-10-29 15:35:33.364 Df wine[81300:28c82a2] [com.apple.metal.hud:Logging] metal-HUD: 6014,619.25,2046.16<private>
    2026-10-29 15:35:33.772 Df wine[81300:28c82a3] [com.apple.metal.hud:Logging] metal-HUD: 6063,619.25,2046.16<private>
    2026-10-29 15:35:34.180 Df wine[81300:28c8286] [com.apple.metal.hud:Logging] metal-HUD: 6112,619.25,2046.16<private>
    """
}
