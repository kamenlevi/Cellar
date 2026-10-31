# Chants of Sennaar: check

Oct 30, 2026 at 22:18, 120 s, D3DMetal. **PASS (automatic part)**

## Automatic

- Launches and keeps running: yes
- Renderer loaded: yes
- Window fills the screen: yes
- Sound playing: not judged (muted for this check)
- Frame rate: 120.0 fps average over 104 s (target 114, display 120 Hz); slowest moment 115 fps; 0 hitches (allowed 2)
- Saves written during the check: yes

## Wine errors

    err:kerberos:kerberos_LsaApInitializePackage no Kerberos support, expect problems
    err:winediag:ntlm_check_version ntlm_auth was not found. Make sure that ntlm_auth >= 3.0.25 is in your path. Usually, you can find it in the winbind package of your distribution.
    err:ntlm:ntlm_LsaApInitializePackage no NTLM support, expect problems
    err:mmdevapi:init_driver No driver from L"pulse,alsa,oss,coreaudio" could be initialized. Maybe check dependencies with WINEDEBUG=warn+module.
    err:dbghelp_msc:codeview_process_info Unknown CODEVIEW signature 00000000 in module L"d3d11"
    err:dbghelp_msc:codeview_process_info Unknown CODEVIEW signature 00000000 in module L"dxgi"
    err:wininet:open_http_connection create_netconn failed: 12029

## Kamen checks

- [ ] reaches gameplay
- [ ] visuals match reference footage
- [ ] music and sound effects, no crackle
- [ ] cutscenes and video
- [ ] keyboard and mouse
- [ ] DualSense, rumble included
- [ ] saves persist, Steam Cloud syncs
- [ ] quit and relaunch is clean
