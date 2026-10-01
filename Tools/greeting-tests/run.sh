#!/bin/sh
# Compile the pure greeting engine with the test main and run every edge
# case across many seeds. No app, no SwiftUI: HomeGreeting.swift depends on
# Foundation and the AuraFamily enum only.
set -e
cd "$(dirname "$0")/../.."
swiftc -o /tmp/greeting_tests \
  Auries/Models/AurieModels.swift \
  Auries/Models/AurieExpressions.swift \
  Auries/Models/AurieLimbCatalog.swift \
  Auries/Models/CharmModels.swift \
  Auries/Models/CharmCatalog.generated.swift \
  Auries/Generation/SeededGenerator.swift \
  Auries/Services/HomeGreeting.swift \
  Tools/greeting-tests/main.swift
/tmp/greeting_tests
