---
name: repowarden
description: Skill repowarden pour agents IA. Déclenche sur ticket, commit, branche, push, PR, CI, gh, action interdite ou refus du garde-fou.
---
<!-- repowarden:skill posée par repowarden agents init ; retirer cette ligne pour la personnaliser -->

# Repowarden

## But
Appliquer le circuit repowarden dans le dépôt : pas de changement sans ticket, conception écrite, `repowarden cc`, PR brouillon par le bot, livraison par le mainteneur.

## Circuit
1. **Ticket créé avant tout changement** (même pour un réglage GitHub). Sans ticket, s'arrêter et en demander un : un agent ne crée un ticket (`repowarden ticket nouveau "<titre>"`) que si on le lui demande, et n'en valide jamais.
2. **Conception** : noter la « Conception retenue » sur le ticket (quoi, fichiers touchés, hors périmètre). Tout écart est noté sur le ticket avant ou au moment.
3. **Prendre le ticket** : `repowarden ticket <n>`. La branche `type/<n>-sujet` est créée depuis `develop`.
4. **Cadrer les essais** : utiliser `./.essai/` pour des dépôts jetables sans remote. Les supprimer à la fin.
5. **Coder et commiter** : `git add <fichiers>` (jamais `git add .`, `-A` ou `--all`). Message via `repowarden cc -m "<description seule>" --type <type> --scope <portée> --body "<pourquoi>" --refs "Ticket : #<n>"` (français, en-tête ≤ 72 caractères, sans signature/agent). Sans `--no-verify`.
6. **Pousser** : `git push -u origin HEAD` sans forcer. Le bot ouvre une PR brouillon vers `develop` avec `Ticket : #<n>` (jamais `Closes #<n>`).
7. **PR** : le mainteneur la passe en ready et livre ; l'agent suit `repowarden pr checks <n>` et signale quand tout est vert. Un agent ne merge pas, ne passe pas une PR en ready, ne ferme pas de ticket. Seul `develop` entre dans `main`, par la PR de livraison.

## Commandes utiles
- `repowarden ticket <n>` / `repowarden ticket comment <n> "<texte>"`
- `repowarden cc --dry-run -m "<description>" --type <type> --scope <portée> --body "<pourquoi>" --refs "Ticket : #<n>"`
- `repowarden pr checks <n>`, `repowarden run rerun <id|--failed|--workflow>`
- `REPOWARDEN_TICKET=<n> gh …` : écriture GitHub hors circuit, rattachée au ticket <n>
- `opencode run --auto "<consigne>" < /dev/null` : opencode non interactif (sans `--auto` chaque permission est refusée, sans `< /dev/null` il attend en silence)

## Garde-fou
Il refuse notamment :
- push direct ou forcé sur `main`/`develop` ;
- `git commit` hors `repowarden cc` ;
- modifier un fichier sur une branche protégée ou hors branche de ticket ;
- écriture `gh` hors circuit sans ticket ;
- valider un ticket ou changer son statut.

Si `repowarden garde` refuse une action : lire le message, appliquer exactement la commande indiquée, ne jamais contourner (`--no-verify`, `--admin`, exception). Un texte entre guillemets citant une commande interdite doit aller dans un fichier. Si le refus semble impossible au regard de la conception du ticket, s'arrêter et l'expliquer sur le ticket, pas d'invention.

## Règles
- Messages français, sans signature ni co-auteur d'agent.
- Bash 3.2 compatible si on touche des scripts shell.
- Un défaut devient un ticket ; s'il est lié à un ticket ouvert, le noter en « Ajout » dessus.
