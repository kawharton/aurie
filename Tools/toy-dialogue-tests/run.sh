#!/bin/sh
# Compile the pure Toy Box dialogue director with the test main and run the
# frequency / pool / overlap rules across many seeds. No app, no SpriteKit:
# ToyDialogue.swift depends on Foundation and the AuraFamily enum only.
set -e
cd "$(dirname "$0")/../.."
swiftc -o /tmp/toy_dialogue_tests \
  Auries/Models/AurieModels.swift \
  Auries/Models/AurieExpressions.swift \
  Auries/Models/AurieLimbCatalog.swift \
  Auries/Models/CharmModels.swift \
  Auries/Models/CharmCatalog.generated.swift \
  Auries/Generation/SeededGenerator.swift \
  Auries/Scenes/ToyDialogue.swift \
  Tools/toy-dialogue-tests/main.swift
/tmp/toy_dialogue_tests
