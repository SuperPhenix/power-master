# Ultimate-Win11-Setup

Script PowerShell "tout-en-un" pour preparer un poste **Windows 11 professionnel** apres une installation fraiche.

## Utilisation

### Une ligne, rien a telecharger (recommande)

```powershell
irm https://raw.githubusercontent.com/SuperPhenix/power-master/main/Ultimate-Win11-Setup.ps1 | iex
```

Le script se telecharge en memoire, demande l'elevation tout seul (nouvelle console admin) et affiche le menu.

### Ou en fichier local

1. Ouvrir PowerShell **en administrateur** (ou laisser le script s'elever tout seul).
2. Autoriser l'execution si besoin :
   ```powershell
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```
3. Lancer :
   ```powershell
   .\Ultimate-Win11-Setup.ps1
   ```

## Modes

| Commande | Effet |
|---|---|
| `.\Ultimate-Win11-Setup.ps1` | Menu interactif une page (sections 1-10, raccourcis A/D/P/Q) |
| `.\Ultimate-Win11-Setup.ps1 -All` | Tout appliquer |
| `.\Ultimate-Win11-Setup.ps1 -All -DryRun` | Previsualiser sans rien modifier |
| `.\Ultimate-Win11-Setup.ps1 -All -SkipDebloat -SkipApps` | Tout, sauf debloat et apps |
| `.\Ultimate-Win11-Setup.ps1 -RunApps -AppList "Git.Git","7zip.7zip"` | Apps specifiques uniquement |
| `.\Ultimate-Win11-Setup.ps1 -RunSecurity -RunNetwork` | Sections choisies uniquement |

## Menu interactif (une seule page)

- Mode courant affiché en haut (NORMAL ou DRYRUN)
- `[1]`-`[10]` : lancer une section, puis retour automatique au menu avec le rapport
- `[A]` : tout appliquer · `[D]` : tout prévisualiser (DryRun) · `[P]` : basculer DryRun · `[Q]` : quitter

## Sections

1. **Debloat** : suppression des apps pre-installees (Xbox, Solitaire, Teams perso, Cortana, jeux, partenaires...) + blocage des apps suggerees
2. **Confidentialite** : telemetrie minimale, ID publicitaire off, Cortana/Bing off, localisation off, historique d'activite off, feedback off, Autorun off
3. **Windows Update** : report feature updates 60j / quality 7j, pas de reboot force, heures actives, Delivery Optimization off
4. **Performance** : plan Hautes performances, hibernation off, effets visuels, delais menus a 0, priorite CPU, throttling reseau off
5. **Shell** : extensions visibles, fichiers caches, "Ce PC" par defaut, barre des taches a gauche, Widgets/Copilot/Chat off, menu contextuel Win10, Snap Assist off
6. **Reseau** : RDP + NLA, DNS Cloudflare (personnalisable via `-DnsServers`), SMBv1 off, chiffrement SMB, pare-feu 3 profils, LLMNR/NetBIOS off
7. **Securite** : UAC durci, Defender (cloud, PUA, protection reseau, anti-ransomware), SmartScreen, BitLocker (verif), NTLMv2 only, WDigest off, verrouillage auto 15 min
8. **Applications** : 19 outils pro via Winget (PowerToys, VS Code, Git, 7-Zip, Chrome, Firefox, VLC, Zoom, Teams pro, Bitwarden, Wireshark, Python...)
9. **Developpement** : WSL2 + Ubuntu, Hyper-V, Windows Sandbox, conteneurs, mode developpeur, chemins longs, config Git, Chocolatey
10. **Maintenance** : purge temp/corbeille, DISM RestoreHealth, SFC, tache planifiee hebdomadaire, gpupdate

## Securite integree

- Point de restauration systeme avant toute modification (desactivable via `-NoRestorePoint`)
- Export des clefs de registre sensibles vers `C:\ProgramData\UltimateWin11Setup\RegistryBackup`
- Journal complet (transcript) dans `C:\ProgramData\UltimateWin11Setup\Logs`
- Mode `DryRun` pour tester sans risque
- Idempotent : relancer ne casse rien
