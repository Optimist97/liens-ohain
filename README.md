# lien ohain

Un espace d’organisation familiale pour partager un planning, des horaires et des nouvelles.

Connexion personnelle requise. Les données sont conservées dans Supabase. Le dépôt et GitHub Pages contiennent uniquement l’application.

## Développement

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm test
pnpm build
```

Configurer Supabase dans `.env.local` à partir de `.env.example`. Ne pas ajouter de données personnelles ni de clés secrètes au dépôt.

## Activité Supabase

GitHub Actions appelle deux fois par jour la fonction légère `activity_check` pour réduire le risque de pause du projet Free. Elle ne consulte ni ne modifie les données familiales. Cette routine ne garantit pas à elle seule l’absence de mise en pause ; surveiller les avis Supabase. GitHub peut désactiver les tâches planifiées après 60 jours sans activité du dépôt.
