#!/usr/bin/env bash
# Python (Django, FastAPI, Flask, scripts…) : ruff/black, pytest ou manage.py test
# Les outils du projet (.venv, uv) sont prioritaires : même version pour tous.
register python "pyproject.toml setup.py setup.cfg requirements.txt Pipfile manage.py" '\.pyi?$' standalone

# Exécute dans l'environnement du projet (uv, poetry, pipenv, .venv)
python_run() {
    if [ -f uv.lock ] && has uv; then uv run --no-sync "$@"
    elif [ -f poetry.lock ] && has poetry; then poetry run "$@"
    elif [ -f Pipfile.lock ] && has pipenv; then pipenv run "$@"
    elif [ -d .venv/bin ]; then PATH="$PWD/.venv/bin:$PATH" "$@"
    elif [ -d .venv/Scripts ]; then PATH="$PWD/.venv/Scripts:$PATH" "$@"
    else "$@"
    fi
}

# Vrai si l'outil $1 est disponible (dans le projet, sinon sur le poste)
python_has() { python_run "$1" --version >/dev/null 2>&1; }

python_format() {
    if python_has ruff; then step_t lang.python.1; python_run ruff format -q "$@"
    elif python_has black; then step "Python : black"; python_run black -q "$@"
    else tool_missing "Python : ni ruff ni black installé, formatage ignoré."
    fi
}

# Vrai si le projet contient des tests : un requirements.txt seul (outils de
# documentation, scripts) ne doit pas exiger pytest.
python_has_tests() {
    [ -f manage.py ] && return 0
    # -quit : premier fichier trouvé suffit (pas de tube vers grep -q : SIGPIPE)
    [ -n "$(find . \( -name node_modules -o -name .venv -o -name .git -o -name site-packages \) -prune -o \
        \( -name 'test_*.py' -o -name '*_test.py' -o -name conftest.py \) -print -quit 2>/dev/null)" ]
}

python_test() {
    local rc=0 cache
    # Cache de bytecode neuf : Python réutilise un .pyc si la source a même taille
    # et même date à la seconde près — fréquent quand le hook met de côté puis
    # restaure des fichiers. Sans ça, les tests tourneraient sur l'ancien code.
    cache="$(mktemp -d)"
    export PYTHONPYCACHEPREFIX="$cache"
    # Django sans pytest-django : runner intégré
    if [ -f manage.py ] && ! grep -qs pytest-django pyproject.toml requirements*.txt setup.cfg Pipfile; then
        step_t lang.python.2
        python_run python manage.py test || rc=$?
        rm -rf "$cache"
        return "$rc"
    fi
    if ! python_has_tests; then info_t lang.python.3; rm -rf "$cache"; return 0; fi
    if ! python_has pytest; then warn_t lang.python.4; rm -rf "$cache"; return 0; fi
    step_t lang.python.5
    # Racine du projet importable (comme « python -m pytest ») : tests/ importe
    # le paquet sans installation ni conftest.py
    PYTHONPATH="$PWD${PYTHONPATH:+:$PYTHONPATH}" python_run pytest -q -p no:cacheprovider || rc=$?
    rm -rf "$cache"
    # 5 = aucun test collecté : pas une erreur
    if [ "$rc" -eq 5 ]; then info_t lang.python.6; return 0; fi
    return "$rc"
}

# Code mort : ruff (imports et variables inutilisés, redéfinitions : prouvé) ;
# vulture (confiance 100 % : prouvé, en dessous : candidat — les frameworks
# appellent des fonctions par leur nom)
python_deadcode() {
    local ran="" a_ruff=0 a_vulture=0
    if python_has ruff; then
        ran=1
        a_ruff=1
        python_run ruff check --select F401,F811,F841 --output-format concise --quiet --exit-zero . 2>/dev/null |
            sed -nE 's/^(.+):([0-9]+):[0-9]+: F[0-9]+ (\[\*\] )?(.*)$/prouve\t\1\t\2\t\4/p'
    fi
    if python_has vulture; then
        ran=1
        a_vulture=1
        python_run vulture . --min-confidence 60 --exclude ".venv,venv,node_modules,build,dist,site-packages" 2>/dev/null |
            sed -nE -e 's/^(.+):([0-9]+): (.*) \(100% confidence\)$/prouve\t\1\t\2\t\3/p' \
                -e 's/^(.+):([0-9]+): (.*) \(([0-9]+)% confidence\)$/candidat\t\1\t\2\t\3 (\4 %)/p'
    fi
    if [ -z "$ran" ]; then
        deadcode_tool_missing Python "ruff / vulture"
    elif [ "$a_ruff" = 0 ]; then
        # vulture seul : les imports et variables inutilisés restent à analyser
        deadcode_partial Python ruff "pip install ruff"
    elif [ "$a_vulture" = 0 ]; then
        # ruff seul : les fonctions et classes inutilisées restent à analyser
        deadcode_partial Python vulture "pip install vulture"
    fi
}
