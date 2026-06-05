# ISTE SCTCE Portal - Multi-Platform Monorepo

Welcome to the restructured ISTE SCTCE Portal codebase! This repository is organized as a unified workspace containing the following components:

## Folder Architecture

```text
├── /lynq          # Execom Native Application (Flutter)
├── /m-lynq        # Member Mobile Application (Flutter)
├── /lynq-site     # Execom Web Platform (React + TypeScript)
├── /shared        # Shared resources, utilities, constants, and assets
│   ├── /constants # Cross-platform configs (JSON, etc.)
│   ├── /dart      # Common Dart models and helpers for mobile apps
│   └── /ts        # Common TypeScript types/utilities for web apps
├── /debug_apk     # Categorized debug builds
│   ├── /lynq      # Execom app debug builds
│   └── /m-lynq    # Member app debug builds
└── /release_apk   # Categorized release builds
    ├── /lynq      # Execom app release builds
    └── /m-lynq    # Member app release builds
```

---

## 1. /lynq (Execom Native App)
- **Framework**: Flutter (Dart)
- **Purpose**: Internal management portal for Core and Forum Execom members to track tasks, approve budgets, draft announcements, and review registrations.
- **Commands**:
  - `cd lynq`
  - `flutter pub get`
  - `flutter run`

## 2. /m-lynq (Member App)
- **Framework**: Flutter (Dart)
- **Purpose**: Student/member application to view events, view digital membership cards, receive notifications, and verify attendance.
- **Commands**:
  - `cd m-lynq`
  - `flutter pub get`
  - `flutter run`

## 3. /lynq-site (Web Portal)
- **Framework**: React + TypeScript + Vite
- **Purpose**: The web dashboard for administrative tasks, reporting, bulk actions, and settings.
- **Commands**:
  - `cd lynq-site`
  - `npm install`
  - `npm run dev` (Development mode)
  - `npm run build` (Production build)

## 4. /shared (Shared Module)
- Used to keep common models, helpers, and assets synchronized across applications to eliminate code duplication.
