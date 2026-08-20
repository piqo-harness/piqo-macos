# Piqo Desktop Beta — guide d’utilisation

Installez le DMG signé puis déplacez Piqo dans Applications. Au premier
lancement, ouvrez **Réglages** et configurez un provider dans
`~/.config/piqo/piqo.toml`. La clé du provider y est volontairement en clair :
protégez votre compte utilisateur et ne partagez jamais ce fichier.

Créez une conversation, choisissez un workspace local, puis le provider et le
modèle avant d’envoyer le premier prompt. Le workspace n’est qu’une métadonnée
locale dans cette bêta ; Piqo n’accorde pas d’accès disque au serveur. Les runs
peuvent être annulés, réessayés et forkés depuis un message terminé.

Piqo ne contacte que son sidecar loopback embarqué, vérifie son démarrage, sa
santé et l’ordre des événements SSE. En cas d’échec, les réglages et diagnostics
restent accessibles. Le protocole v1 ne fournit aucun endpoint pour tester les
identifiants provider.

Limites v1 : pas de pièces jointes, outils, permissions interactives, résultats
d’outils, sous-agents, daemon distant, renommage/archivage/suppression de
session ni lecture directe de `piqo.db`. Les demandes d’action ou de permission
sont affichées comme bloquées.
