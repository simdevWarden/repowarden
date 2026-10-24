# shellcheck shell=bash
# Suivi des tickets, premier push d'une branche de ticket (PR brouillon) et
# revues (ci/tickets.sh push, revue).
# Chargé par ci/tickets.sh (après hooks/lib/common.sh et hooks/lib/tickets.sh).
# shellcheck disable=SC2154 # statuts, réglages et compteurs définis dans les autres modules

# REPLY = rang d'impact du sujet de commit $1 : 0 rupture, 1 feat, 2 fix/perf,
# 3 autre type conforme
rang_impact() {
    case "$1" in
        *"!: "*) REPLY=0 ;;
        feat*:*) REPLY=1 ;;
        fix*:* | perf*:*) REPLY=2 ;;
        *) REPLY=3 ;;
    esac
}

# REPLY = sujet du commit conforme de plus fort impact de la branche $1, vide
# si aucun commit conforme (repli du titre de PR quand le ticket n'en donne pas)
commit_impact_r() {
    local s rang meilleur="" meilleur_rang=""
    REPLY=""
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        [[ "$s" =~ $CC_PATTERN ]] || continue
        rang_impact "$s"
        rang="$REPLY"
        if [ -z "$meilleur" ] || [ "$rang" -lt "$meilleur_rang" ]; then
            meilleur="$s"
            meilleur_rang="$rang"
        fi
    done < <(gh api "repos/$GH_REPO/compare/$INTEGRATION...$1" \
        -q '.commits[].commit.message | split("\n")[0]' 2>/dev/null || true)
    REPLY="$meilleur"
}

# REPLY = en-tête du premier commit de la branche $1 par rapport à la branche
# d'intégration, sans « (#N) » final ; vide s'il n'est pas utilisable (aucun
# commit, non conforme, plus de 72 caractères). Lu par l'API : le checkout du
# workflow est celui de repowarden, pas l'historique du projet.
premier_commit_r() {
    local s
    s="$(gh api "repos/$GH_REPO/compare/$INTEGRATION...$1" \
        -q '.commits[0].commit.message // "" | split("\n")[0] // ""' 2>/dev/null || true)"
    s="${s%%$'\n'*}"
    s="${s%$'\r'}"
    [[ "$s" =~ ^(.*[^[:space:]])[[:space:]]+\(#[0-9]+\)$ ]] && s="${BASH_REMATCH[1]}"
    REPLY=""
    [[ "$s" =~ $CC_PATTERN ]] || return 0
    authored_length "$s"
    [ "$REPLY" -le 72 ] || { REPLY=""; return 0; }
    REPLY="$s"
}

# REPLY = titre de la PR brouillon du ticket $1 (branche $2) : en-tête du
# premier commit de la branche (déjà validé par les hooks, il devient le commit
# de squash), sinon « type(portée): sujet » depuis le ticket, sinon le commit
# conforme de plus fort impact, sinon le titre déduit de la branche
titre_pr_brouillon_r() {
    local n="$1" branche="$2" type
    premier_commit_r "$branche"
    [ -z "$REPLY" ] || return 0
    ticket_type_r "$(etiquettes "$n")"
    type="$REPLY"
    ticket_pr_title_r "$type" "$(gh issue view "$n" --json title -q .title)"
    [ -z "$REPLY" ] || return 0
    commit_impact_r "$branche"
    [ -z "$REPLY" ] || return 0
    suggest_pr_title_r "$branche"
}

# $1 = corps d'un ticket → REPLY : ses sections de critères d'acceptation
# (« Terminé quand… », « Critères d'acceptation ») en cases à cocher « - [ ] »,
# RESTE_TICKET : le reste (constat, proposition), que la PR replie
criteres_coches_r() {
    local corps="$1" ligne dedans=0 criteres="" reste=""
    while IFS= read -r ligne; do
        ligne="${ligne%$'\r'}"
        if [[ "$ligne" =~ ^#{1,6}[[:space:]] ]]; then
            dedans=0
            case "$ligne" in
                *[Tt]ermin* | *[Cc]rit* | *[Aa]cceptance* | *[Dd]one*) dedans=1 ;;
            esac
        elif [ "$dedans" = 1 ]; then
            # « - x » → « - [ ] x » ; une case déjà là n'est pas dupliquée
            ligne="$(printf '%s' "$ligne" |
                sed -E 's/^([[:space:]]*[-*][[:space:]]+)(\[[xX ]\][[:space:]]+)?/\1[ ] /')"
        fi
        if [ "$dedans" = 1 ]; then
            criteres="$criteres$ligne"$'\n'
        else
            reste="$reste$ligne"$'\n'
        fi
    done <<<"$corps"
    while [[ "$reste" == $'\n'* ]]; do reste="${reste#$'\n'}"; done
    sans_fin_vide_r "$reste"
    RESTE_TICKET="$REPLY"
    sans_fin_vide_r "$criteres"
}

# Fin de chaque commentaire lu d'un bloc (séparateur ASCII) : un texte écrit à
# la main ne le contient pas, les commentaires se découpent sans ambiguïté
SEP_COMMENTAIRE=$'\x1e'

# REPLY = commentaires de mainteneur du ticket $1, chacun suivi d'une ligne
# SEP_COMMENTAIRE : comme la conception, seul un mainteneur alimente la PR
commentaires_mainteneur_r() {
    REPLY="$(gh issue view "$1" --json comments -q '.comments[]
        | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR")
        | .body + "\n\u001e"' 2>/dev/null || true)"
}

# $1 = ligne d'un commentaire → REPLY : titre décalé d'un niveau (rangé sous la
# section du bot), ligne citée si pr_tickets_r la lirait : seul le pied compte
ligne_reprise_r() {
    REPLY="$1"
    [[ ! "$REPLY" =~ ^#{1,5}[[:space:]] ]] || REPLY="#$REPLY"
    [[ ! "$REPLY" =~ $REF_TICKET_RE ]] || REPLY="> $REPLY"
}

# $1 = texte → REPLY : sans ses lignes vides finales
sans_fin_vide_r() {
    REPLY="$1"
    while [[ "$REPLY" == *$'\n' ]]; do REPLY="${REPLY%$'\n'}"; done
}

# Première ligne d'un commentaire d'ajout : titre ou gras « Ajout… », « Constat lié… »
AJOUT_RE='^(#{1,6}[[:space:]]+|\*\*)?([Aa]jouts?|[Cc]onstats?[[:space:]]+li(é|e)s?)([[:space:]:*(.,-]|$)'

# $1 = commentaires (commentaires_mainteneur_r) → REPLY : ceux dont la première
# ligne est un titre ou un gras « Ajout » / « Constat lié », dans l'ordre :
# les ajouts faits au ticket après coup, que le corps du ticket n'a pas
ajouts_ticket_r() {
    local ligne bloc="" premiere="" sortie=""
    while IFS= read -r ligne; do
        ligne="${ligne%$'\r'}"
        if [ "$ligne" = "$SEP_COMMENTAIRE" ]; then
            if [[ "$premiere" =~ $AJOUT_RE ]]; then
                sans_fin_vide_r "$bloc"
                sortie="$sortie${sortie:+$'\n\n'}$REPLY"
            fi
            bloc="" premiere=""
            continue
        fi
        if [ -z "$premiere" ]; then
            [ -n "${ligne//[[:space:]]/}" ] || continue
            premiere="$ligne"
        fi
        ligne_reprise_r "$ligne"
        bloc="$bloc$REPLY"$'\n'
    done <<<"$1"$'\n'"$SEP_COMMENTAIRE"
    REPLY="$sortie"
}

# $1 = commentaires → REPLY : du dernier « Conception retenue », les blocs « Ce
# qui change » et « Hors périmètre » (titre ou gras, jusqu'au libellé suivant) :
# le périmètre sans les détails (fichiers, tests) que montre déjà le diff
resume_conception_r() {
    local ligne bloc="" dernier="" garder=0 conception=0
    while IFS= read -r ligne; do
        ligne="${ligne%$'\r'}"
        if [ "$ligne" = "$SEP_COMMENTAIRE" ]; then
            [ "$conception" = 0 ] || dernier="$bloc"
            bloc="" garder=0 conception=0
            continue
        fi
        if [[ "$ligne" =~ ^(#{1,6}[[:space:]]|\*\*) ]]; then
            garder=0
            case "$ligne" in
                *[Cc]onception\ retenue*) conception=1; continue ;;
                *[Cc]e\ qui\ change* | *[Hh]ors\ p*) garder=1 ;;
            esac
        fi
        [ "$garder" = 1 ] || continue
        ligne_reprise_r "$ligne"
        bloc="$bloc$REPLY"$'\n'
    done <<<"$1"$'\n'"$SEP_COMMENTAIRE"
    sans_fin_vide_r "$dernier"
}

# $1 = description actuelle de la PR → REPLY : sa dernière section « ## Réalisé »
# (jusqu'au titre suivant ou au pied), écrite par l'auteur : reprise telle quelle
section_realise_r() {
    local ligne dedans=0 section=""
    while IFS= read -r ligne; do
        ligne="${ligne%$'\r'}"
        if [[ "$ligne" =~ ^##[[:space:]]+R(é|e)alis(é|e) ]]; then
            dedans=1 section="$ligne"$'\n'
        elif [ "$dedans" = 1 ]; then
            if [[ "$ligne" =~ ^#{1,2}[[:space:]] || "$ligne" == "Ticket : #"* ]]; then
                dedans=0
            else
                section="$section$ligne"$'\n'
            fi
        fi
    done <<<"$1"
    sans_fin_vide_r "$section"
}

# Ligne de pied d'un commit (`repowarden cc --refs`), faite seulement de
# références : retirée, le pied de la PR porte déjà le ticket
PIED_COMMIT_RE='^[[:space:]]*(Tickets?|Refs?|Closes|Fixes|Resolves)[[:space:]]*:?[[:space:]]*#[0-9]+([[:space:],]+#[0-9]+)*[[:space:]]*$'

# $1 = commits lus par l'API (« parents sha message », chacun suivi d'une ligne
# SEP_COMMENTAIRE) → REPLY : pour chaque commit hors fusion, « ### en-tête (sha) »
# puis son corps, le pourquoi que le relecteur cherche avant le ticket
ce_que_fait_r() {
    local ligne debut=1 fusion=0 entete="" bloc="" sortie="" reste
    while IFS= read -r ligne; do
        ligne="${ligne%$'\r'}"
        if [ "$ligne" = "$SEP_COMMENTAIRE" ]; then
            if [ -n "$entete" ] && [ "$fusion" = 0 ]; then
                sans_fin_vide_r "$bloc"
                sortie="$sortie${sortie:+$'\n\n'}$entete${REPLY:+$'\n'}$REPLY"
            fi
            debut=1 fusion=0 entete="" bloc=""
            continue
        fi
        if [ "$debut" = 1 ]; then
            [ -n "$ligne" ] || continue
            debut=0
            # plus d'un parent : commit de fusion, sans rien à dire à la revue
            [ "${ligne%% *}" -le 1 ] 2>/dev/null || fusion=1
            reste="${ligne#* }"
            entete="### ${reste#* } (${reste%% *})"
            continue
        fi
        [ -n "$bloc" ] || [ -n "${ligne//[[:space:]]/}" ] || continue
        [[ ! "$ligne" =~ $PIED_COMMIT_RE ]] || continue
        ligne_reprise_r "$ligne"
        bloc="$bloc$REPLY"$'\n'
    done <<<"$1"$'\n'"$SEP_COMMENTAIRE"
    REPLY="$sortie"
}

# REPLY = description de la PR brouillon du ticket $1 (branche $2, PR $3 si
# elle existe) : ce que fait la PR (corps des commits), les critères du ticket
# en cases à cocher, ses ajouts en commentaire, le résumé de sa conception, le
# reste du ticket replié, la section « Réalisé » de l'auteur gardée, puis
# « Ticket : #N ». Le bot ne régénère que ses sections.
description_pr_brouillon_r() {
    local n="$1" branche="$2" pr="${3:-}" corps="" reste commentaires
    ce_que_fait_r "$(gh api "repos/$GH_REPO/compare/$INTEGRATION...$branche" \
        -q '.commits[] | "\(.parents | length) \(.sha[0:7]) \(.commit.message)\n\u001e"' 2>/dev/null || true)"
    _tr tk.pr_does
    [ -z "$REPLY" ] || corps="## $_T"$'\n'"$REPLY"
    criteres_coches_r "$(gh issue view "$n" --json body -q .body)"
    reste="$RESTE_TICKET"
    [ -z "$REPLY" ] || corps="$corps${corps:+$'\n\n'}$REPLY"
    commentaires_mainteneur_r "$n"
    commentaires="$REPLY"
    ajouts_ticket_r "$commentaires"
    _tr tk.pr_additions
    [ -z "$REPLY" ] || corps="$corps${corps:+$'\n\n'}## $_T"$'\n'"$REPLY"
    resume_conception_r "$commentaires"
    _tr tk.pr_design
    [ -z "$REPLY" ] || corps="$corps${corps:+$'\n\n'}## $_T"$'\n'"$REPLY"
    if [ -n "$reste" ]; then
        # lignes vides autour du texte : sinon GitHub ne rend pas son Markdown
        _tr tk.pr_ticket "$n"
        corps="$corps${corps:+$'\n\n'}<details>"$'\n'"<summary>$_T</summary>"$'\n\n'"$reste"$'\n\n</details>'
    fi
    if [ -n "$pr" ]; then
        section_realise_r "$(gh pr view "$pr" --json body -q .body 2>/dev/null || true)"
        [ -z "$REPLY" ] || corps="$corps${corps:+$'\n\n'}$REPLY"
    fi
    REPLY="$corps${corps:+$'\n\n'}Ticket : #$n"
}

# Premier push sur la branche d'un ticket : PR brouillon vers la branche
# d'intégration, titrée par le premier commit (repli : le ticket), à la
# description reprise du ticket, citant le
# ticket, assignée à l'auteur du push ; ticket en cours. Ouverte par le jeton
# des Actions, elle ne lance pas la CI : elle tourne au push suivant, ou au
# passage « prête pour revue ». Tant qu'elle est en brouillon, chaque push met
# à jour son titre et sa description ; une PR prête n'est plus touchée.
cmd_push() {
    local n pr titre corps url
    : "${PUSH_BRANCH:?}" "${SHA:?}"
    [ "${DELETED:-false}" != true ] || return 0
    branch_ticket_r "$PUSH_BRANCH"
    n="$REPLY"
    [ -n "$n" ] || return 0
    # Branche faite hors du ticket (à la main) : inscrite sur le ticket
    inscrire_branche "$n" "$PUSH_BRANCH"
    pr="$(gh pr list --state open --head "$PUSH_BRANCH" --json number -q '.[0].number // empty')"
    # PR existante : rien à faire si elle n'est plus en brouillon
    [ -z "$pr" ] || [ "$(gh pr view "$pr" --json isDraft -q .isDraft)" = true ] || return 0
    [ "$(gh api "repos/$GH_REPO/compare/$INTEGRATION...$PUSH_BRANCH" -q .ahead_by)" != 0 ] || return 0
    titre_pr_brouillon_r "$n" "$PUSH_BRANCH"
    titre="$REPLY"
    description_pr_brouillon_r "$n" "$PUSH_BRANCH" "$pr"
    corps="$REPLY"
    if [ -n "$pr" ]; then
        gh pr edit "$pr" --title "$titre" --body "$corps" >/dev/null
        notice_t tk.draft_updated "$pr" "$n"
        return 0
    fi
    url="$(gh pr create --draft --base "$INTEGRATION" --head "$PUSH_BRANCH" --title "$titre" \
        --body "$corps" ${PUSHER:+--assignee "$PUSHER"})"
    [ -z "${PUSHER:-}" ] || gh issue edit "$n" --add-assignee "$PUSHER" >/dev/null || true
    est_valide "$n" && statut "$n" "$S_ENCOURS"
    notice_t tk.draft_opened "${url##*/}" "$n"
    verifier "${url##*/}" "$SHA" "$n" "$PUSH_BRANCH" || true
}

# Revue : corrections demandées → le ticket repasse en cours
cmd_revue() {
    local body n
    : "${PR:?}" "${HEAD:?}"
    [ "${REVIEW_STATE:-}" = changes_requested ] || return 0
    body="$(gh pr view "$PR" --json body -q .body)"
    pr_tickets_r "$body" "$HEAD"
    for n in $REPLY; do
        est_valide "$n" && statut "$n" "$S_ENCOURS"
    done
    return 0
}
