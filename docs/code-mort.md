# Code mort

Du code est **mort** quand on peut **prouver** qu'il n'a aucun effet sur le comportement du programme. repowarden distingue trois cas, qui ne se prouvent pas de la même façon :

| Catégorie | Définition | Exemples | Preuve | repowarden |
|---|---|---|---|---|
| **Inaccessible** | instructions qu'aucun chemin d'exécution n'atteint | code après un `return`, `if (false)` | analyse du flot de contrôle | **prouvé** : bloquant |
| **Inutilisé dans sa portée** | déclaration jamais référencée là où elle est visible | import, variable locale, paramètre ou membre **privé** jamais lus | analyse des références du fichier | **prouvé** : bloquant |
| **Non référencé dans le projet** | élément visible de l'extérieur que rien dans le projet n'utilise | méthode publique, export, fichier, dépendance | graphe d'appels depuis les points d'entrée | **candidat** : avertissement |

Les deux premiers cas sont certains : l'outil ne devine rien. Le troisième ne l'est pas toujours, car du code peut être appelé **sans référence visible** :

- réflexion et injection (beans Spring, `Class.forName`, `getattr`) ;
- appels depuis l'extérieur : API publique d'une bibliothèque, routes HTTP, tâches planifiées ;
- sérialisation (Jackson, JPA), templates, configuration, autre langage.

C'est pourquoi un **candidat** n'est jamais bloquant par défaut : un humain confirme.

## Seulement le nouveau code mort

repowarden ne signale que le code mort **introduit** par la PR (lignes ajoutées ou modifiées depuis la base). Un projet existant n'est pas noyé sous son historique : la dette ne grossit plus, et on la réduit à son rythme.

## Outils, par langage

| Langage | Prouvé | Candidats |
|---|---|---|
| Java (Maven, Gradle) | PMD : imports, champs, méthodes et variables privés inutilisés | — (Spring et réflexion rendent l'analyse trop incertaine) |
| TypeScript / JavaScript | `tsc` : variables, paramètres, imports inutilisés, code inaccessible | [knip](https://knip.dev) s'il est installé dans le projet : fichiers, exports, dépendances |
| Python | ruff (F401, F811, F841), vulture à 100 % de confiance | vulture en dessous de 100 % (le pourcentage est affiché) |
| Go | staticcheck (U1000 : identifiants non exportés inutilisés) | — |

En CI, l'action installe PMD pour un projet Java (version et empreinte figées). Les autres outils sont ceux du projet. Un outil absent est signalé, sans faire échouer même le mode strict : la détection reste une aide.

## Analyse partielle

Quand un langage a plusieurs outils (Python : ruff et vulture ; JavaScript : `tsc` et knip) et qu'il n'en est installé qu'un seul, l'analyse est **partielle** : repowarden le signale en nommant ce qui n'a pas été analysé (« Python : vulture absent : fonctions et classes inutilisées non analysées (pip install vulture) »). Et surtout, sans résultat sur ce qui a été analysé, le message de fin n'est plus le feu vert « Aucun nouveau code mort », mais « Aucun nouveau code mort dans ce qui a été analysé : analyse partielle, voir ci-dessus ». Aucun outil du langage n'est là : le message « code mort non analysé » reste, et compte aussi comme une analyse partielle.

## Utilisation

- **CI** : vérification `deadcode`, incluse par défaut dans l'action (`checks:`).
- **Poste** : `repowarden code-mort [base]` analyse ta branche comme la CI : commits, modifications en cours et nouveaux fichiers. Base par défaut : `origin/main` ; sur une branche sans modification, rien n'est analysé.

## Réglages

```ini
[repowarden]
    deadcode = block               # défaut : le prouvé bloque, les candidats avertissent
    # deadcode = warn              # rien ne bloque
    # deadcode = strict            # candidats bloquants aussi
    deadcodeIgnore = src/generated/* legacy/*   # chemins ignorés
    # skip = deadcode              # désactiver la vérification
```

Un faux positif ponctuel se déclare aussi avec l'annotation de l'outil (`@SuppressWarnings("PMD.UnusedPrivateMethod")`, `# noqa: F401`, `// @ts-expect-error`…), visible en revue.
