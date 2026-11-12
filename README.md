# PlochaPro AR – měření kamerou iPhonu (jako apka Měření)

Nativní iPhone apka (SwiftUI + ARKit). Míříš křížkem, mačkáš ＋, měří vzdálenost na centimetry nebo plochu obrysu (podlaha, zeď). Na iPhonech Pro s LiDARem je přesnější. Výsledek (fotka + rozměry) jde sdílet třeba do Zpráv nebo uložit.

## Jak ji dostat do iPhonu z Windows (zdarma)

### 1) Sestavení na GitHubu (jednou, pak automaticky)
1. Na GitHubu vytvoř **veřejný** repozitář `plochapro-ar`.
2. Nahraj do něj obsah téhle složky (včetně `.github/workflows/build.yml`).
3. Záložka **Actions** → běh „Sestavit iPhone apku“ (trvá ~5 minut).
4. Až je zelený: otevři ho → dole **Artifacts** → stáhni `PlochaProAR-ipa` a rozbal zip → máš `PlochaProAR.ipa`.

### 2) Nahrání do iPhonu přes Windows
1. Nainstaluj **iTunes** (verzi z webu apple.com, ne z Microsoft Store) a **Sideloadly** (sideloadly.io).
2. Připoj iPhone kabelem, na iPhonu potvrď „Důvěřovat tomuto počítači“.
3. V Sideloadly přetáhni `PlochaProAR.ipa`, zadej svoje Apple ID a dej **Start**.
4. Na iPhonu: Nastavení → Soukromí a zabezpečení → **Režim vývojáře** → zapnout (telefon se restartuje).
5. Nastavení → Obecné → **Správa VPN a zařízení** → tvoje Apple ID → Důvěřovat.

### Omezení bezplatného Apple ID
- Apka platí **7 dní**, pak ji stejně znovu nahraješ v Sideloadly (data se nesmažou).
- Max. 3 takové apky najednou.
- Bez obou omezení by to bylo jen s placeným Apple Developer účtem (99 USD/rok).

## Soubory
- `*.swift` – zdrojový kód apky, `icon-512.png` – ikona
- `project.yml` – popis projektu pro XcodeGen (Xcode projekt se vytvoří až na GitHubu)
- `.github/workflows/build.yml` – automatické sestavení na Macu od GitHubu
