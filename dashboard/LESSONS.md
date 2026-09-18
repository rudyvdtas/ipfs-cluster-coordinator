# Security review lessons

## Bevindingen

Deze lijst is gebaseerd op een statische review van de huidige `main`-branch. Het is geen volledige penetratietest.

- **Hoog — ontbrekende authenticatie en autorisatie:** het dashboard wordt via Traefik gepubliceerd zonder zichtbare authenticatie, autorisatie, IP-beperking of TLS-configuratie.
- **Hoog — gevoelige clusterinformatie kan uitlekken:** zonder toegangscontrole kunnen peer IDs, IPFS IDs, netwerkadressen, versies, peer-namen, pin-statussen en CIDs zichtbaar worden.
- **Hoog — cluster-REST-API moet intern blijven:** controleer dat `CLUSTER_API_URL` en poort `9094` niet rechtstreeks vanaf het internet bereikbaar zijn.
- **Middel/hoog — interne foutdetails worden aan gebruikers getoond:** `String(e)` en response bodies van de cluster-API worden rechtstreeks in de response gezet.
- **Middel — requests hebben geen timeout:** `fetch()` naar de cluster-API gebruikt geen `AbortController`; een trage of vastgelopen backend kan serverresources bezet houden.
- **Middel — responses zijn niet begrensd:** `/pins` wordt volledig ingelezen en verwerkt. Een zeer grote response kan onnodig veel geheugen en CPU gebruiken.
- **Middel — ontbrekende security headers:** er is geen zichtbare CSP, HSTS, `X-Content-Type-Options`, `Referrer-Policy` of `Permissions-Policy`.
- **Middel/laag — container hardening ontbreekt:** de productie-image stelt geen expliciete non-root user in en kopieert de volledige `node_modules` uit de builder-stage.
- **Nog te verifiëren — dependencies:** voer `npm audit`, `npm outdated` en een container/image-scan uit; uit een statische bronreview kan niet worden vastgesteld of alle dependencyversies vrij zijn van bekende CVE's.

## Aanpak en stappen

### 1. Toegang tot het dashboard beperken

- Kies een toegangsmodel: SSO/basic auth via Traefik, VPN, private network of een IP-allowlist.
- Voeg HTTPS/TLS toe en voorkom een productie-deployment met `dashboard.localhost` als standaardhostnaam.
- Controleer dat het dashboard niet publiek bereikbaar is voordat authenticatie is toegevoegd.
- Voeg tests toe die anonieme requests afwijzen.

### 2. De cluster-API afschermen

- Bind de cluster-API alleen aan het interne Docker-netwerk.
- Controleer firewall- en reverse-proxyregels voor poort `9094`.
- Gebruik authenticatie of een service credential als de cluster-API dit ondersteunt.
- Zorg dat secrets uitsluitend via runtime environment/secrets management worden aangeleverd en nooit in Git staan.

### 3. Foutafhandeling veilig maken

- Log details server-side met een request-ID.
- Stuur naar de browser alleen een generieke foutmelding.
- Geef geen upstream response body, interne URL, stack trace of configuratiewaarde terug.
- Test expliciet fouten van de cluster-API met gevoelige inhoud in de response body.

### 4. Requests robuust maken

- Voeg een timeout toe met `AbortController`.
- Beperk responsegrootte en het maximaal aantal pins dat wordt verwerkt.
- Gebruik waar passend pagination of een server-side limiet.
- Voeg rate limiting en caching toe als het dashboard publiek of breed toegankelijk is.
- Test timeouts, malformed JSON, onverwacht grote responses en upstream 5xx-responses.

### 5. Security headers toevoegen

- Configureer minimaal CSP, HSTS bij HTTPS, `X-Content-Type-Options: nosniff`, `Referrer-Policy` en `Permissions-Policy`.
- Beperk framing met `frame-ancestors` in CSP of `X-Frame-Options`.
- Controleer de headers met OWASP ZAP, Mozilla Observatory of een vergelijkbare scanner.

### 6. Container en dependencies hardenen

- Laat de runtime-container expliciet als non-root user draaien.
- Installeer alleen production dependencies in de runtime-stage.
- Pin of verifieer base images en scan images met Trivy of Docker Scout.
- Voer in CI `npm ci`, `npm audit --audit-level=high`, tests en de container-scan uit.
- Activeer Dependabot of Renovate voor gecontroleerde updates.

### 7. Validatie voor release

- Voer een dependency-scan uit.
- Voer een secret-scan uit op de volledige Git-history, niet alleen op de huidige bestanden.
- Test anonieme toegang, foutmeldingen, timeouts, grote responses en security headers.
- Controleer Docker-, Traefik-, firewall- en cloud security-groepen samen; veilige applicatiecode compenseert geen publiek blootgestelde backend-poorten.
- Herhaal de review na iedere wijziging aan authenticatie, proxying, clustercommunicatie of deployment.

## Leerpunten

- **Server-side code is niet automatisch privé:** data die door een `load`-functie wordt geretourneerd, kan onderdeel worden van de browserresponse.
- **Een interne default-URL is geen netwerkbeveiliging:** `http://cluster:9094` voorkomt alleen een verkeerde hostnaam; Docker-netwerken en firewallregels moeten toegang daadwerkelijk beperken.
- **Foutmeldingen zijn een gegevensuitvoer:** upstream response bodies kunnen net zo gevoelig zijn als succesvolle data.
- **Beschikbaarheid hoort bij security:** timeouts, rate limits, response-limieten en pagination verkleinen het DoS-risico.
- **Defence-in-depth is noodzakelijk:** authenticatie, netwerkisolatie, headers, veilige logging, container hardening en dependencybeheer vullen elkaar aan.
- **Een statische review heeft grenzen:** dependency-CVE's, runtimeconfiguratie, Docker-netwerken en echte toegangscontrole moeten ook dynamisch worden getest.

## Definition of done

- [ ] Dashboard vereist authenticatie of is aantoonbaar alleen intern bereikbaar.
- [ ] Cluster-API en poort `9094` zijn niet publiek bereikbaar.
- [ ] Productie gebruikt HTTPS en passende security headers.
- [ ] Foutmeldingen bevatten geen interne details.
- [ ] Alle upstream requests hebben timeouts en response-limieten.
- [ ] Runtime-container draait als non-root.
- [ ] Dependency-, secret- en container-scans draaien in CI.
- [ ] Securitytests voor de bovenstaande scenario's zijn toegevoegd.
