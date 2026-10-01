#!/bin/sh
# Compile the production charm model sources with the test main and run.
set -e
cd "$(dirname "$0")/../.."
swiftc -o /tmp/charm_model_tests \
  Auries/Models/CharmModels.swift \
  Auries/Models/CharmCatalog.generated.swift \
  Auries/Models/CharmTasks.swift \
  Auries/Services/CharmCollection.swift \
  Auries/Services/PurchaseService.swift \
  Auries/Services/HatchWallet.swift \
  Auries/Models/AurieModels.swift \
  Auries/Models/AurieExpressions.swift \
  Auries/Models/AurieLimbCatalog.swift \
  Auries/Generation/SeededGenerator.swift \
  Auries/Services/AurieCollectionCodec.swift \
  Tools/charm-tests/main.swift
/tmp/charm_model_tests
