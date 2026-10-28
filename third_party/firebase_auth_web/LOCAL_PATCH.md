# Local patch: Firebase Auth Web 6.3.0

Upstream: https://pub.dev/packages/firebase_auth_web/versions/6.3.0
License preserved in LICENSE. Only lib/src/interop/auth.dart differs.

When the explicit recovery page writes gerenciador_horas.auth.storage=local,
initialize Auth with browserLocalPersistence and browserSessionPersistence only. IndexedDB must be excluded
before SDK initialization, not only after sign-in, since the SDK checks all
persistence backends during restoration/migration. Unmarked profiles retain
the upstream hierarchy. The app uses the same preference for sign-in.

Do not remove this override until initialization supports this selection
upstream, or recovery profiles can access IndexedDB again. Never store raw
passwords in this preference; Firebase manages its normal session tokens.
