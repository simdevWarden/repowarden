#!/usr/bin/env bash
# Tickets côté poste et côté CI : numéro du ticket d'une branche, nom de la
# branche d'un ticket, suivi des tickets géré ou non par repowarden.
# Chargé après common.sh. Compatible bash 3.2.
# shellcheck disable=SC2034 # statuts utilisés par les scripts qui chargent ce fichier

# Statuts (étiquettes) du cycle d'un ticket
VALIDE="validé"
S_AVALIDER="statut: à valider"
S_BACKLOG="statut: backlog"
S_ENCOURS="statut: en cours"
S_RELECTURE="statut: en relecture"
S_PREPROD="statut: préprod"
S_DONE="statut: done"
# Posée à l'ouverture : pas de validation d'office, un mainteneur décide
A_DECIDER="à décider"
# Types de ticket (étiquettes « type: … », préfixe de la branche)
TYPES_TICKET="feat fix docs refactor chore"

# Vrai si les étiquettes $1 (une par ligne) disent le travail terminé : mergé
# (préprod) ou en production (done). Un tel ticket n'a plus de branche à créer.
travail_termine() { grep -qxF -e "$S_PREPROD" -e "$S_DONE" <<<"$1"; }

# REPLY = numéro du ticket porté par la branche $1 (type/12-sujet, type/12),
# vide sinon
branch_ticket_r() {
    REPLY=""
    if [[ "$1" =~ ^[a-z]+/([0-9]+)(-|$) ]]; then REPLY="${BASH_REMATCH[1]}"; fi
}

# $1 → sans accents (un à un : les classes [àâ] sont fausses en locale C) ;
# les autres caractères sont conservés, le nettoyage reste à l'appelant
sans_accents() {
    printf '%s' "$1" | sed -e 's/à/a/g' -e 's/â/a/g' -e 's/ä/a/g' -e 's/é/e/g' -e 's/è/e/g' -e 's/ê/e/g' -e 's/ë/e/g' -e 's/î/i/g' -e 's/ï/i/g' -e 's/ô/o/g' -e 's/ö/o/g' -e 's/ù/u/g' -e 's/û/u/g' -e 's/ü/u/g' -e 's/ç/c/g' -e 's/œ/oe/g' -e 's/æ/ae/g' -e 's/À/a/g' -e 's/Â/a/g' -e 's/Ä/a/g' -e 's/É/e/g' -e 's/È/e/g' -e 's/Ê/e/g' -e 's/Ë/e/g' -e 's/Î/i/g' -e 's/Ï/i/g' -e 's/Ô/o/g' -e 's/Ö/o/g' -e 's/Ù/u/g' -e 's/Û/u/g' -e 's/Ü/u/g' -e 's/Ç/c/g' -e 's/Œ/oe/g' -e 's/Æ/ae/g'
}

# Mots vides qu'un nom de branche (ou une portée) ne garde pas en fin de coupe :
# « …-garde-la-trace-de » → « …-garde-la-trace »
MOTS_VIDES="a au aux de des du en et l la le les of on ou par pour sur the to un une"

# $1 (minuscules, tirets) → sans ses mots vides finaux
sans_mots_vides() {
    local slug="$1" mot
    while [[ "$slug" == *-* ]]; do
        mot="${slug##*-}"
        [[ " $MOTS_VIDES " == *" $mot "* ]] || break
        slug="${slug%-*}"
    done
    printf '%s' "$slug"
}

# REPLY = nom de branche d'un ticket : $1 numéro, $2 titre, $3 type (feat
# par défaut) → feat/12-ajoute-le-panier (minuscules, sans accents, 40
# caractères au plus, coupé sur un tiret puis sur un mot entier)
ticket_branch_r() {
    local n="$1" titre="$2" type="${3:-feat}" slug
    slug="$(sans_accents "$titre" | LC_ALL=C tr '[:upper:]' '[:lower:]' |
        LC_ALL=C sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
    if [ "${#slug}" -gt 40 ]; then
        slug="${slug:0:40}"
        [[ "$slug" == *-* ]] && slug="${slug%-*}"
    fi
    slug="$(sans_mots_vides "$slug")"
    REPLY="$type/$n${slug:+-$slug}"
}

# REPLY = titre de PR d'un ticket : $1 type (« feat » par défaut), $2 titre du
# ticket → « feat(portée): sujet ». Portée = préfixe du titre avant le premier
# « : » (« Tickets : … » → « tickets »), 20 caractères au plus, omise si vide ;
# sujet = le reste, première lettre abaissée sauf sur un sigle (README, IA :
# initiale suivie d'une majuscule). 72 caractères au plus, coupé à la dernière
# espace, jamais dans un mot. Vide si le titre ne donne rien (l'appelant décide
# du repli).
ticket_pr_title_r() {
    local type="${1:-feat}" titre="$2" portee sujet tete res
    sujet="$titre"
    portee=""
    if [[ "$titre" =~ ^([^:]{1,30})[[:space:]]*:[[:space:]]+(.+)$ ]]; then
        portee="$(sans_accents "${BASH_REMATCH[1]}" | LC_ALL=C tr '[:upper:]' '[:lower:]' |
            LC_ALL=C sed -e 's/[^a-z0-9._-]\{1,\}/-/g' -e 's/^-//' -e 's/-$//')"
        [ "${#portee}" -le 20 ] || portee=""
        sujet="${BASH_REMATCH[2]}"
    fi
    [[ "${sujet:1:1}" == [[:upper:]] ]] ||
        sujet="$(printf '%s' "${sujet:0:1}" | LC_ALL=C tr '[:upper:]' '[:lower:]')${sujet:1}"
    tete="$type${portee:+($portee)}: "
    REPLY=""
    [ -n "$sujet" ] || return 0
    res="$tete$sujet"
    # 72 caractères au plus, coupé sur un mot entier (authored_length → REPLY) ;
    # un mot seul trop long n'est pas tronqué : titre vide
    authored_length "$res"
    while [ "$REPLY" -gt 72 ] && [ -n "$sujet" ]; do
        if [[ "$sujet" == *" "* ]]; then sujet="${sujet% *}"; else sujet=""; fi
        res="$tete$sujet"
        authored_length "$res"
    done
    [ -n "$sujet" ] || res=""
    REPLY="$res"
}

# REPLY = type de branche d'après les étiquettes d'un ticket (une par ligne) :
# « type: fix », « bug » → fix ; feat par défaut
ticket_type_r() {
    local l
    REPLY=feat
    while IFS= read -r l; do
        case "$l" in
            "type: "*) REPLY="${l#type: }"; return 0 ;;
            bug) REPLY=fix ;;
        esac
    done <<<"$1"
}

# Registre des branches d'un ticket : repère invisible dans les commentaires
# du bot. GitHub ne lie une branche au ticket qu'à sa création, et une branche
# liée supprimée y perd son nom : le registre garde le nom de chaque branche.
REPERE="repowarden:branche"

repere() { printf '<!-- %s %s -->' "$REPERE" "$1"; }

# REPLY = branches inscrites sur le ticket $1 (séparées par des espaces)
branches_inscrites_r() {
    local corps
    corps="$(gh issue view "$1" --json comments -q '.comments[].body' 2>/dev/null || true)"
    REPLY="$(grep -oE "<!-- $REPERE [^ ]+ -->" <<<"$corps" | awk '{ printf "%s ", $3 }' || true)"
    REPLY="${REPLY% }"
}

# REPLY = adresse de la branche $2 si elle n'est pas liée au ticket $1, vide si
# elle l'est ou si GitHub ne répond pas (dans le doute, on ne signale rien)
ticket_unlinked_branch_url_r() {
    local lignes url
    REPLY=""
    # shellcheck disable=SC2016 # variables GraphQL, pas du shell
    lignes="$(gh api graphql -F owner='{owner}' -F repo='{repo}' -F n="$1" -f query='query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) { url issue(number: $n) { linkedBranches(first: 50) { nodes { ref { name } } } } }
}' -q '.data.repository.url, .data.repository.issue.linkedBranches.nodes[].ref.name' 2>/dev/null)" || return 0
    url="${lignes%%$'\n'*}"
    [ -n "$url" ] || return 0
    grep -qxF "$2" <<<"$lignes" || REPLY="$url/tree/$2"
}

# Branche $2 du ticket $1 créée avant sa validation : GitHub ne lie pas une
# branche existante (createLinkedBranch répond null), son lien est donc inscrit
# sur le ticket, une seule fois. Vrai si le commentaire a été posté.
ticket_note_unlinked_branch() {
    local n="$1" b="$2" url
    ticket_unlinked_branch_url_r "$n" "$b"
    url="$REPLY"
    [ -n "$url" ] || return 1
    branches_inscrites_r "$n"
    [[ " $REPLY " != *" $b "* ]] || return 1
    _tr tk.branch_unlinked "$b" "$url"
    gh issue comment "$n" --body "$_T"$'\n\n'"$(repere "$b")" >/dev/null
}

# Vrai si la branche $1 est une branche de travail : ni protégée, ni une
# exception (main, develop, branches des bots…)
work_branch() {
    local branch="$1" pat
    [ -n "$branch" ] || return 1
    cfg_r allowedBranches "$DEFAULT_ALLOWED_BRANCHES"
    set -f
    for pat in $REPLY; do
        # shellcheck disable=SC2254
        case "$branch" in $pat) set +f; return 1 ;; esac
    done
    set +f
    cfg_r protectedBranches "main master"
    [[ " $REPLY " != *" $branch "* ]]
}

# Vrai si le suivi des tickets du projet est géré par repowarden : réglage
# tickets (true/false), sinon un workflow du dépôt appelle tickets.yml
TICKETS_MANAGED=""
tickets_managed() {
    local f
    if [ -z "$TICKETS_MANAGED" ]; then
        TICKETS_MANAGED=non
        cfg_r tickets ""
        case "$REPLY" in
            true | oui | yes) TICKETS_MANAGED=oui ;;
            false | non | no) ;;
            *)
                for f in "$GIT_TOPLEVEL"/.github/workflows/*.yml "$GIT_TOPLEVEL"/.github/workflows/*.yaml; do
                    [ -f "$f" ] || continue
                    if grep -qsE 'uses:.*workflows/tickets\.ya?ml' "$f"; then TICKETS_MANAGED=oui; break; fi
                done
                ;;
        esac
    fi
    [ "$TICKETS_MANAGED" = oui ]
}

# Vrai si la création automatique de ticket est activée : réglage
# ticketAutoCreate = true (défaut false)
TICKET_AUTO_CREATE=""
ticket_auto_create() {
    if [ -z "$TICKET_AUTO_CREATE" ]; then
        TICKET_AUTO_CREATE=non
        cfg_r ticketAutoCreate ""
        case "$REPLY" in
            true | oui | yes) TICKET_AUTO_CREATE=oui ;;
            false | non | no | "") ;;
        esac
    fi
    [ "$TICKET_AUTO_CREATE" = oui ]
}

# Branche de travail sans ticket : avertissement, jamais bloquant. Création
# proposée seulement si repowarden gère la vie des tickets du projet (et que
# gh est là pour la faire) ; sinon, comment faire taire l'avertissement.
ticket_hint() {
    local branch="$1"
    skipped tickets && return 0
    work_branch "$branch" || return 0
    branch_ticket_r "$branch"
    [ -z "$REPLY" ] || return 0
    attention_t tk.cli.no_ticket "$branch"
    dim_t tk.cli.explain
    if tickets_managed && has gh; then
        # git cc ne propose de créer le ticket qu'avec ticketAutoCreate
        if ticket_auto_create; then dim_t tk.cli.propose_cc; else dim_t tk.cli.propose; fi
    else
        dim_t tk.cli.silence
    fi
}

# REPLY = branche d'où partent les tickets : integrationBranch, sinon la branche
# par défaut du dépôt distant
ticket_base_r() {
    cfg_r integrationBranch ""
    [ -z "$REPLY" ] || return 0
    REPLY="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
    REPLY="${REPLY#origin/}"
}

# REPLY = branche distante (origin) du ticket $1 (type/<n>-…), vide si aucune
ticket_remote_branch_r() {
    local ref
    REPLY=""
    while IFS= read -r ref; do
        ref="${ref#origin/}"
        branch_ticket_r "$ref"
        if [ "$REPLY" = "$1" ]; then REPLY="$ref"; return 0; fi
        REPLY=""
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)
}

# Branches locales des tickets qui me sont assignés (repowarden tickets sync ;
# hooks post-merge et post-checkout seulement si ticketSync = auto est posé,
# au plus toutes les 15 min) :
# branche distante retrouvée, ou créée et liée au ticket (validé) ; branche
# locale de suivi créée sans changer la branche courante (jamais pour un travail
# livré : préprod, done, ou en relecture sans branche). Ticket qui ne m'est
# plus assigné : signalé, sa branche locale conservée. Réglage ticketSync :
# manual (défaut : commande seulement, un pull ne touche à rien), auto, off. $1 = force (commande).
tickets_sync() {
    local force="${1:-}" stamp now last base n titre etiquettes branche b qui etat
    local miens=" "
    cfg_r ticketSync manual
    [ "$REPLY" != off ] || return 0
    if [ -z "$force" ]; then
        [ "$REPLY" = auto ] && tickets_managed && command -v gh >/dev/null || return 0
        stamp="$(git rev-parse --git-common-dir)/repowarden-ticket-sync"
        now="$(date +%s)"
        last="$(cat "$stamp" 2>/dev/null || echo 0)"
        [ $((now - last)) -ge "${REPOWARDEN_TICKET_SYNC_EVERY:-900}" ] || return 0
        echo "$now" >"$stamp"
        gh auth status >/dev/null 2>&1 || return 0
    fi
    git fetch -q origin --prune 2>/dev/null || return 0
    ticket_base_r
    base="$REPLY"
    while IFS=$'\t' read -r n titre etiquettes; do
        [ -n "$n" ] || continue
        miens="$miens$n "
        etiquettes="${etiquettes//\\n/$'\n'}"
        travail_termine "$etiquettes" && continue
        ticket_remote_branch_r "$n"
        branche="$REPLY"
        if [ -z "$branche" ]; then
            # En relecture sans branche : PR mergée, branche supprimée ; jamais recréée
            grep -qxF "$S_RELECTURE" <<<"$etiquettes" && continue
            if tickets_managed && ! grep -qxF "$VALIDE" <<<"$etiquettes"; then
                info_t tk.sync.not_validated "$n"
                continue
            fi
            ticket_type_r "$etiquettes"
            ticket_branch_r "$n" "$titre" "$REPLY"
            branche="$REPLY"
            if ! gh issue develop "$n" --name "$branche" --base "$base" >/dev/null 2>&1 ||
                ! git fetch -q origin "$branche" 2>/dev/null; then
                attention_t tk.sync.failed "$n"
                continue
            fi
        fi
        git show-ref -q --verify "refs/heads/$branche" && continue
        git branch -q --track "$branche" "origin/$branche" && ok_t tk.sync.ready "$n" "$branche" "$n"
    done < <(gh issue list --assignee @me --state open --limit 100 --json number,title,labels \
        -q '.[] | [.number, .title, ([.labels[].name] | join("\n"))] | @tsv' 2>/dev/null || true)
    while IFS= read -r b; do
        branch_ticket_r "$b"
        n="$REPLY"
        if [ -z "$n" ] || [[ "$miens" == *" $n "* ]]; then continue; fi
        IFS=$'\t' read -r etat qui <<<"$(gh issue view "$n" --json state,assignees \
            -q '[.state, ([.assignees[].login] | join(", "))] | @tsv' 2>/dev/null || true)"
        if [ "$etat" != OPEN ] || [ -z "$qui" ]; then continue; fi
        info_t tk.sync.reassigned "$n" "$qui" "$b"
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)
    return 0
}
