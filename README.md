# 🧠 NEXUS-IA

![Status](https://img.shields.io/badge/Status-Active-success)
![Architecture](https://img.shields.io/badge/Architecture-Systemic-blue)
![Performance](https://img.shields.io/badge/Benchmark-High--Performance-orange)
![License](https://img.shields.io/badge/License-Apache_2.0-blue)

> **Un modèle linguistique souverain et systémique.** Conçu pour surpasser les architectures cloud centralisées (Gemini, Carbon, Argon) en termes de performance, de latence et de contrôle.

---

## 🚀 Ce qui rend NEXUS-IA différent

Ce n'est pas un chatbot de plus. C'est un **moteur linguistique autonome** conçu pour les environnements système exigeants.

### 1. Performances mesurées (Pas de promesses)
- **Latence locale** : NEXUS opère dans un environnement local optimisé.
- **Architecture** : Conçu pour tourner avec un minimum d'overhead, sans dépendance à une API cloud externe.
- **Comparatif** : Les benchmarks locaux démontrent une réactivité supérieure aux modèles hébergés, avec une consommation mémoire contrôlée.

### 2. Intégration Systémique
NEXUS-IA n'est pas isolé. Il fait partie d'un écosystème :
- **KOLLAMA** : Le lanceur de modèles locaux (remplaçant d'Ollama).
- **RUSTAVA** : Le compilateur natif pour l'optimisation des performances.
- **NEXUS GEN HUB** : L'orchestrateur de workflows.

### 3. Souveraineté Totale
- **Local-First** : Le modèle tourne sur votre machine (pas de fuite de données).
- **Open-Source** : Licence Apache 2.0. Vous pouvez auditer chaque ligne de code.

---

## 🛠️ Démarrage Rapide

Puisque le modèle pèse plusieurs Go, il n'est pas versionné directement dans ce dépôt. Voici comment le lancer :

### Prérequis
- Ollama (ou un lanceur compatible GGUF).
- Les binaires de base (fournis dans les Releases).

### Installation
```bash
# 1. Cloner le dépôt
git clone https://github.com/Aissamohammedi88/nexus-ia.git
cd nexus-ia

# 2. Télécharger le modèle (voir l'onglet Releases)
# Placez le fichier nexus-axiom-ai.gguf dans ce dossier.

# 3. Créer le modèle dans Ollama
cat > Modelfile << 'EOF'
FROM ./nexus-axiom-ai.gguf
PARAMETER temperature 0.7
PARAMETER num_ctx 4096
SYSTEM "Tu es Nexus Axiom, une IA souveraine. Réponds de manière technique et directe."
EOF

# 4. Compiler et lancer
sudo ollama create nexus-axiom-ai -f Modelfile
ollama run nexus-axiom-ai
