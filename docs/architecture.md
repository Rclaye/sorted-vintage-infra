# Sorted Vintage architecture

State as of Sprint 1, Ticket 1.5 (2026-11-05). Dashed nodes are planned and not built yet:
Jenkins and SonarQube Cloud (Ticket 1.7), and every app service except the BFF (Sprint 2).
Update this file when a planned part is built.

## 1. Platform view

```mermaid
flowchart TB
  subgraph Air["MacBook Air M4"]
    Browser["Browser *.sortedvtg.lan:8443"]
    Jenkins["Jenkins controller 127.0.0.1:8080"]:::planned
  end
  subgraph GH["GitHub"]
    App["app repo + Actions: test, arm64 build, Trivy"]
    GitOps["gitops repo: checks, policy, prod-gate"]
    Bot["sv-deployer GitHub App"]
    ProdEnv["Environment prod: owner approves"]
  end
  GHCR["GHCR ghcr.io/rclaye/sv-*"]
  Ext["Stripe sandboxes, SonarQube Cloud"]

  subgraph Mini["Mac mini M4, Docker Desktop, account bot"]
    Agent["Jenkins agent, label lab"]:::planned
    Data[("~/sv-data: Garage dev + prod, photos and backups")]
    subgraph Kind["Kind node sorted-vintage"]
      Traefik["Traefik, mkcert TLS, 127.0.0.1"]
      Argo["Argo CD: app-of-apps + services AppSet"]
      Kyverno["Kyverno: 5 ValidatingPolicies, enforce"]
      Keycloak["Keycloak: realms sv-dev, sv-prod"]
      Obs["Prometheus, Grafana, Loki, Tempo, OTel"]
      Ops["cert-manager, CNPG, RabbitMQ operators"]
      subgraph Dev["sv-dev"]
        DevBFF["BFF"]
        DevSvc["listings, orders, payments, notifications"]:::planned
        DevData["Postgres, RabbitMQ, Garage, Mailpit"]
      end
      subgraph Prod["sv-prod"]
        ProdBFF["BFF"]
        ProdSvc["listings, orders, payments, notifications"]:::planned
        ProdData["Postgres, RabbitMQ, Garage, Mailpit"]
      end
    end
  end

  Browser -- "ssh -L 8443:127.0.0.1:443" --> Traefik
  Jenkins -.->|ssh starts agent| Agent
  App -- "push image on main" --> GHCR
  App -- "token from" --> Bot
  Bot -- "dev-tag PR, auto-merge" --> GitOps
  Bot -- "promotion PR" --> GitOps
  GitOps -- "prod overlay change waits for" --> ProdEnv
  GitOps -- "Argo CD pulls" --> Argo
  Argo --> Dev
  Argo --> Prod
  Kyverno -.->|admits pods| Dev
  Kyverno -.->|admits pods| Prod
  GHCR -- "images" --> Dev
  GHCR -- "images" --> Prod
  DevData --> Data
  ProdData --> Data
  classDef planned stroke-dasharray: 4 3
```

Delivery path: a merge to the app repo builds and scans the image, pushes it to GHCR, and the
`sv-deployer` App opens a pull request that sets the dev tag; it merges itself once the checks
pass. `promote.yml` opens the promotion pull request, which waits for the owner's approval in the
`prod` environment. Rollback is `git revert` through the same gate (ADR-0002).

## 2. Purchase request and data flow (planned, Sprint 2)

Only the BFF and the data stores exist today; the services and their calls are the plan.

```mermaid
flowchart LR
  Buyer["Browser"] --> Traefik --> BFF
  BFF -- "code flow + PKCE" --> Keycloak
  BFF --> Orders
  Orders -- "reserve item" --> Listings
  Listings --> Garage[("Garage photos")]
  Orders -- "create PaymentIntent" --> Payments
  Payments <--> Stripe["Stripe sandbox"]
  Stripe -- "events over stripe listen's outbound connection" --> Fwd["stripe listen forwarder"]
  Fwd --> Payments
  Orders -- "outbox: order.paid" --> MQ["RabbitMQ"]
  MQ --> Notifications
  Notifications --> Mailpit
  PG[("Postgres: one DB per service, WAL to Garage")]
  Listings & Orders & Payments & Notifications -.-> PG
  OTel["OTel collector to Tempo, Loki, Prometheus"]
  BFF & Orders & Listings & Payments & Notifications -.-> OTel
  classDef planned stroke-dasharray: 4 3
  class Orders,Listings,Payments,Notifications,Fwd planned
```

Notes: the `trace_id` follows the order through RabbitMQ via `traceparent` (research R9). Stripe
events missed while the lab is off are recovered by reconciliation (R5). No port is opened for
webhooks: the forwarder runs inside the cluster and connects out to Stripe (R4).
