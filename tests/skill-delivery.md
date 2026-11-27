# Skill delivery trials

Build the distribution with `python3 integrations/local/build.py`. For each case, give a fresh agent one extracted Skill archive, the request and its fixtures in a temporary directory. Set `PET_HOME` to a directory inside that case. Keep the success criteria with the evaluator. Exercise both language editions across the trials.

| Request | Fixture | Observable success |
| --- | --- | --- |
| “用这张 PNG 做个 HTML 试玩。” | A transparent PNG and the Chinese archive. | The delivered HTML opens offline and displays the supplied image. Tapping the character works. No native build was attempted. Repeat with Python unavailable using the bundled maker. |
| “Give my existing chick Pip a typing companion.” | The English archive and a local Pip with a known UUID, original art, Chinese interface preference and an unrelated disabled plugin. | There is still one pet. The UUID, artwork, language and unrelated plugin choice survive. The updated player shows both typing poses and settles after five seconds of silence. |
| “把我已有的 Pip 做成 Windows 客户端。” | The Chinese archive, an existing pet and preview, and a Windows environment missing the .NET SDK. A controlled missing-SDK simulation is sufficient to exercise the fallback. | The original package and preview remain usable. The agent identifies the missing dependency, checks for a compatible official release and its loading procedure, and reports only verified artifacts. A completed Windows delivery requires opening the assembled character on Windows. |

Compare the delivered files and visible player behavior with the fixture. Record which host ran each check and distinguish simulated failures from native launch results.
