# Installateur Zenq Addons

Un seul programme, accessible au lecteur d'écran, pour **installer et mettre à jour** :

- les addons Zenq pour Sku (SkuBagnonBridge, GatherMate2 SKU Access, SkuQuestNearby, SkuQuestTarget, SkuAllyBeacon, SkuAuctionatorBridge, SkuCraftStock, SkuDive, SkuHunterAlerts, SkuQuestJournal, SkuTrainerNews, SkuZoneWaypoints, SkinningInfo, SkuVoiceProbe) ;
- **Sku** lui-même, en téléchargeant et lançant son installateur officiel (qui gère aussi les sons de balise, les données audio et l'outil de connexion) ;
- les addons tiers courants : Questie, TomTom, GatherMate2 et ses données, AtlasLootClassic, Deadly Boss Mods (cœur, donjons, raids BC et Vanilla), Details, Pawn, Bagnon, Auctionator et ses compléments, la suite Auctioneer, Hear Kitty, Lazy Feed Pet, EasyGuildInvite, Smart Guild Inviter.

Chaque addon est une **case à cocher** (« Tout cocher » / « Tout décocher »), avec son état lu dans la case : *non installé, disponible 1.3.0* ; *installé 1.0.2, mise à jour 1.3.0 disponible* ; *à jour (1.3.0)*. Les cases cochées, le dossier WoW, la version du jeu et les options sont **mémorisés** d'une fois sur l'autre. La progression est annoncée au lecteur d'écran (notification UIA, NVDA et JAWS), en option aussi par la voix Windows.

## Installation

1. Télécharge `ZenqAddons-Installateur.zip` et extrais-le où tu veux (par exemple dans *Documents*).
2. Ouvre **« Installateur Zenq Addons.cmd »**. Windows peut demander une confirmation la première fois (fichier téléchargé) : « Exécuter ».
3. Le dossier World of Warcraft est trouvé tout seul (registre Battle.net, disques) ; sinon le bouton « Dossier WoW... » le demande. La version du jeu se choisit dans la liste (Anniversary par défaut).
4. Coche ce que tu veux, puis **« Installer ou mettre à jour la sélection »**. À la fin, un résumé est annoncé et affiché. Un nouveau dossier d'addon demande un vrai redémarrage de WoW.

Sans téléchargement, depuis un terminal PowerShell :

```powershell
irm https://zenqfr.github.io/sku-addons/installer/ZenqAddons.ps1 | iex
```

## En ligne de commande

```
ZenqAddons.ps1 -NoGui -Check                       état de tous les addons
ZenqAddons.ps1 -NoGui -Install Questie,SkuDive     installe ou met à jour ces identifiants
ZenqAddons.ps1 -NoGui -All                         tout ce qui est coché
ZenqAddons.ps1 -WowPath "D:\Jeux\World of Warcraft" -Flavor anniversary
```

## Comment ça marche

- Le **catalogue** `https://zenqfr.github.io/sku-addons/catalog.json` dit quels addons existent et où les prendre : versions GitHub (fichiers de release), fichiers CurseForge (la liste publique du site, sans clé), et l'installateur officiel de Sku pour Sku.
- La version installée est lue dans le `.toc` de chaque addon ; ce que l'installateur a posé lui-même est noté dans `%APPDATA%\ZenqAddons\installed.json`, ce qui rend la détection des mises à jour exacte dès la deuxième fois.
- Un dossier remplacé est supprimé puis réécrit depuis l'archive ; les réglages du jeu (`WTF`) ne sont jamais touchés.
- Réglages : `%APPDATA%\ZenqAddons\settings.json`. Journal : `%APPDATA%\ZenqAddons\journal.log` (bouton « Ouvrir le journal »).
- L'installateur se met à jour lui-même quand le catalogue annonce une version plus récente (il demande avant).

Windows 10 ou 11, Windows PowerShell 5.1 (présent d'origine). Aucune donnée n'est envoyée nulle part : seuls GitHub, CurseForge et cette page sont contactés, en lecture.

---

# Zenq Addons Installer (English)

One screen-reader-friendly program to **install and update** the Zenq companion addons for Sku, Sku itself (by downloading and starting its official installer) and the usual third-party addons (Questie, DBM, Details, Auctionator, Bagnon, GatherMate2, Pawn, TomTom, AtlasLoot, Auctioneer, Hear Kitty…). One checkbox per addon, "Check all / Uncheck all", state read in the checkbox text, choices remembered between runs, progress announced through UIA notifications. Download `ZenqAddons-Installateur.zip`, extract it, open `Installateur Zenq Addons.cmd`. The language switches with the "Français / English" button.
