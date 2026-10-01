#!/usr/bin/env bash
#
# Alta de las verticales contra un despliegue que ya está corriendo.
#
# Es la Parte A del runbook —declarar la línea de negocio y registrar la credencial de servicio de
# cada vertical— hecha contra Platform y no a mano. Existe porque ese procedimiento vivía sólo en
# prosa, y una instrucción en prosa no la cumple nadie: este despliegue llevó días arriba con las
# cuatro APIs corriendo y sin una sola línea declarada.
#
# Lo que eso produce no es una caída. Sin credencial que Platform reconozca, el servicio de la
# vertical pregunta por su línea, recibe 401, lo anota como advertencia y arranca igual — que es la
# decisión correcta: negarse convertiría una caída de Platform en la caída de todas las verticales.
# El costo es que el aviso queda en el log de un contenedor que nadie mira, y por eso el estado se
# puede sostener indefinidamente sin que nada lo diga.
#
#   USO
#     ./scripts/alta-vertical.sh            # mide y NO escribe nada (es lo que hace por omisión)
#     ./scripts/alta-vertical.sh aplicar    # hace el alta
#
#   DÓNDE
#     Desde el directorio del despliegue: el que tiene `.env` y `docker-compose.yml`.
#
#   POR QUÉ HABLA DESDE ADENTRO DE LA RED
#     Platform está publicada **sólo para su webhook** —ver el Caddyfile— así que desde afuera
#     `/api/v1/auth/login` da 404. Esto comparte el namespace de red del contenedor de Platform,
#     que además no depende de cómo se llame el proyecto de compose.
#
#   SECRETOS
#     La contraseña del administrador se lee del `.env` de esta máquina y nunca se imprime. Ni ella
#     ni el token viajan por la línea de comandos: van en archivos de 0600 montados de sólo lectura,
#     así que no aparecen en `ps` ni en el historial del shell.
#
#     El secreto de cada credencial lo genera Platform y **se devuelve una sola vez**. Este script
#     lo escribe derecho al `.env` sin pasarlo por pantalla. Si se pierde no hay forma de releerlo:
#     el único camino es revocar la credencial y registrar otra.
#
set -euo pipefail

# MSYS —Git Bash en Windows— reescribe los argumentos que parecen rutas absolutas antes de que
# docker los vea, así que `/req/curl.cfg` llegaría adentro del contenedor como `C:/Program Files/…`.
# En Linux esta variable no hace nada; acá es lo que permite ensayar el guion contra una pila local
# antes de correrlo contra un despliegue — que es como se encontraron tres defectos de este archivo.
export MSYS_NO_PATHCONV=1

MODO="${1:-medir}"
case "$MODO" in
  medir|aplicar) ;;
  *) echo "uso: $0 [medir|aplicar]" >&2; exit 2 ;;
esac
APLICA=false; [ "$MODO" = "aplicar" ] && APLICA=true
FALLA_VERTICAL=0

# ───────────────────────────────────────────────────────── las verticales de este despliegue
#
# Una por línea: código, nombre visible, prefijo de sus variables en el `.env`, y su servicio de
# compose. Sumar una tercera es una línea más acá y nada más — la misma propiedad que ya tienen el
# Caddyfile y el registro de verticales del frontend.
VERTICALES=(
  "tourism|Turismo|TOURISM|tourism-api"
  "automotive|Automotriz|AUTOMOTIVE|automotive-api"
)

# Los alcances de cada credencial, por audiencia, y qué rompe cada uno si falta:
#
#   evaluations.request    PIMA       la insignia no se puede evaluar
#   evaluations.read       PIMA       la vertical no puede releer lo que pidió
#   directory.read         PIMA       la ficha pública y el buscador responden 503
#   possession.read        Platform   no puede preguntar quién probó qué contacto
#   businesslines.resolve  Platform   arranca sin haber confirmado su línea, y lo dice en el log
SCOPES_PIMA='["evaluations.request","evaluations.read","directory.read"]'
SCOPES_PLATFORM='["possession.read","businesslines.resolve"]'

# ───────────────────────────────────────────────────────────────────────────────── herramientas
log()   { printf '%s\n' "$*"; }
head1() { printf '\n── %s\n' "$*"; }
fatal() { printf '\n✗ %s\n' "$*" >&2; exit 1; }

[ -f .env ]               || fatal "No hay .env acá. Corré esto desde el directorio del despliegue."
[ -f docker-compose.yml ] || fatal "No hay docker-compose.yml acá."

if   docker compose version >/dev/null 2>&1;    then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else fatal "No encuentro docker compose."; fi

# El mensaje del arranque es la PRIMERA línea que escribe el servicio, no la última: buscarlo en la
# cola es mirar donde no está. `grep -m1` corta en la primera coincidencia y cierra el pipe, así que
# esto no recorre el log entero de un contenedor que lleva días arriba.
# El patrón no contiene ni una letra acentuada, y eso no es estilo. El servicio escribe «Línea de
# negocio…»; un patrón como `l.nea` falla con la locale sin definir, porque ahí `.` casa **un byte**
# y la `í` ocupa dos. Dio un falso NEGATIVO —el alta había funcionado y el guion informó que no—,
# que es mejor que al revés y sigue siendo inaceptable. Se busca por la parte sin acentos.
linea_arranque() { $DC logs "$1" 2>/dev/null | grep -aim1 -E "de negocio|Platform rechaz" || true; }

# ─────────────────────────────────────────────────────────────────────────── el lector de JSON
#
# Sin creerle a `command -v`, que dice que el programa existe y no que funcione: en Windows
# `python3` suele ser un acceso directo a la tienda que sale con 49 sin leer nada.
JSON_LECTOR=""
if printf '{"a":"ok"}' | jq -r .a 2>/dev/null | grep -qx ok; then
  JSON_LECTOR=jq
else
  for cand in python3 python; do
    if printf '{"a":"ok"}' | "$cand" -c 'import sys,json;print(json.load(sys.stdin)["a"])' 2>/dev/null \
       | tr -d '\r' | grep -qx ok; then
      JSON_LECTOR="$cand"; break
    fi
  done
fi
[ -n "$JSON_LECTOR" ] || fatal "Hace falta jq o python para leer las respuestas de Platform, y ninguno contestó."

if [ "$JSON_LECTOR" = jq ]; then
  jget() { jq -r "$1" 2>/dev/null | tr -d '\r' || true; }
else
  # `chr(10)` y no una barra invertida a propósito: este bloque pasa por el shell antes de llegar a
  # Python, y una secuencia de escape acá se come fácil. La primera versión tenía justo eso, con un
  # salto de línea real adentro de una cadena: Python moría con un error de sintaxis, el
  # `2>/dev/null` se lo tragaba, y **todas** las lecturas devolvían vacío sin que nada fallara.
  jget() { "$JSON_LECTOR" -c '
import sys, json
ruta = sys.argv[1]
try: d = json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
if ruta.startswith(".[]|."):
    campo = ruta[5:]
    print(chr(10).join(str(x.get(campo, "")) for x in (d if isinstance(d, list) else [])))
else:
    v = d.get(ruta[1:]) if isinstance(d, dict) else None
    print("" if v is None else (json.dumps(v) if isinstance(v, (dict, list)) else str(v)))
' "$1" 2>/dev/null | tr -d '\r' || true; }
fi

# Y acá se ejerce **el jget de verdad**, no un one-liner parecido. Un lector que existe, arranca y
# devuelve vacío es peor que uno que falta: el guion sigue y no encuentra nada en ningún lado.
printf '{"a":"ok"}' | jget .a | grep -qx 'ok' \
  || fatal "El lector de JSON (${JSON_LECTOR}) no devuelve un campo simple."
[ "$(printf '[{"code":"uno"},{"code":"dos"}]' | jget '.[]|.code' | grep -c .)" = "2" ] \
  || fatal "El lector de JSON (${JSON_LECTOR}) no devuelve una lista."

# Comilla una cadena como literal JSON, sin suponer que no trae comillas ni barras.
jstr() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/'; }

# ─────────────────────────────────── hablar con Platform, sin nada en la línea de comandos
PLATFORM_CID="$($DC ps -q platform-api || true)"
[ -n "$PLATFORM_CID" ] || fatal "platform-api no está corriendo. Levantá la pila primero."

CURL_IMG="curlimages/curl:latest"
docker image inspect "$CURL_IMG" >/dev/null 2>&1 || docker pull -q "$CURL_IMG" >/dev/null

REQ="$(mktemp -d)"; chmod 700 "$REQ"
RESP="$(mktemp)";   chmod 600 "$RESP"
trap 'rm -rf "$REQ"; rm -f "$RESP"' EXIT

# Lo que docker monta tiene que ser una ruta del host, y bajo Git Bash una ruta MSYS no lo es.
# En Linux `cygpath` no existe y esto devuelve lo mismo que recibe.
host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
REQ_HOST="$(host_path "$REQ")"

TOKEN=""

# papi <método> <ruta> [cuerpo-json]
#   deja el cuerpo de la respuesta en $RESP y escribe el código HTTP por stdout.
#   El cuerpo de la respuesta no se imprime nunca acá: puede traer el secreto.
papi() {
  local metodo="$1" ruta="$2" cuerpo="${3:-}"
  {
    printf 'silent\nshow-error\n'
    printf 'write-out = "%s"\n' '\n%{http_code}'
    printf 'request = "%s"\n' "$metodo"
    printf 'url = "http://localhost:8080%s"\n' "$ruta"
    [ -n "$TOKEN" ] && printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"
    if [ -n "$cuerpo" ]; then
      printf 'header = "Content-Type: application/json"\n'
      printf 'data = "@/req/body.json"\n'
      printf '%s' "$cuerpo" > "$REQ/body.json"
    fi
  } > "$REQ/curl.cfg"
  chmod 600 "$REQ"/*

  local salida
  salida="$(docker run --rm --network "container:${PLATFORM_CID}" \
              -v "${REQ_HOST}:/req:ro" "$CURL_IMG" --config /req/curl.cfg)"
  printf '%s' "${salida%$'\n'*}" > "$RESP"
  printf '%s' "${salida##*$'\n'}"
  rm -f "$REQ/body.json" "$REQ/curl.cfg"
}

# ─────────────────────────────────────────────────────────────────── el `.env` de este host
# Se lee sin `source`, para no ejecutar nada de un archivo de configuración.
envget() { sed -n "s/^${1}=//p" .env | head -1 | tr -d '\r'; }

ADMIN_EMAIL="$(envget BOOTSTRAP_EMAIL)"
ADMIN_PASS="$(envget BOOTSTRAP_PASSWORD)"
[ -n "$ADMIN_EMAIL" ] || fatal "BOOTSTRAP_EMAIL no está en el .env."
[ -n "$ADMIN_PASS"  ] || fatal "BOOTSTRAP_PASSWORD no está en el .env."

log "Despliegue:    $(pwd)"
log "Modo:          ${MODO}$([ "$APLICA" = false ] && echo '   — no escribe nada')"
log "Administrador: ${ADMIN_EMAIL}"
log "Lector JSON:   ${JSON_LECTOR}"

# ───────────────────────────────────────────────── 0 · qué dijo cada vertical al arrancar
head1 "0 · lo que dijo cada vertical al arrancar"
for v in "${VERTICALES[@]}"; do
  IFS='|' read -r CODE NOMBRE PREFIJO SERVICIO <<<"$v"
  log "  ${SERVICIO}: $(linea_arranque "$SERVICIO" || true)"
done
log ""
log "  Cómo leerlo:"
log "    «… confirmada en Platform»                 la línea existe y está activa"
log "    «Platform rechazó … Falta la credencial»   arrancó sin poder preguntar — es esto"
log "    (vacío, y el servicio reinicia en bucle)   la línea no está declarada o está retirada"

# ──────────────────────────────────────────────────────────────────── 1 · entrar a Platform
head1 "1 · entrar a Platform"
login_body() {
  if [ -n "${1:-}" ]; then
    printf '{"email":%s,"password":%s,"scopeType":%s}' \
      "$(jstr "$ADMIN_EMAIL")" "$(jstr "$ADMIN_PASS")" "$(jstr "$1")"
  else
    printf '{"email":%s,"password":%s}' "$(jstr "$ADMIN_EMAIL")" "$(jstr "$ADMIN_PASS")"
  fi
}

st="$(papi POST /api/v1/auth/login "$(login_body)")"
[ -n "$st" ] || fatal "El login no devolvió código HTTP: la llamada a Platform no salió."
[ "$st" = "200" ] || fatal "El login respondió ${st}. Revisá BOOTSTRAP_EMAIL y BOOTSTRAP_PASSWORD."

TOKEN="$(jget .accessToken <"$RESP")"
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  # Una cuenta con más de un alcance no recibe token: recibe la lista para elegir. Un 200 sin
  # sesión se parece mucho a un éxito, y por eso esto se comprueba en vez de suponerse.
  log "  La cuenta tiene más de un alcance; eligiendo el de plataforma."
  st="$(papi POST /api/v1/auth/login "$(login_body Platform)")"
  TOKEN="$(jget .accessToken <"$RESP")"
fi
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] \
  || fatal "Entré pero no obtuve sesión. ¿El administrador tiene alcance de plataforma?"
log "  Sesión de plataforma obtenida."

# ──────────────────────────────────────────────────────────────── 2 · lo que ya hay allá
head1 "2 · lo que ya existe en Platform"
papi GET "/api/v1/business-lines?includeInactive=true" >/dev/null
LINEAS="$(jget '.[]|.code' <"$RESP" | sed '/^$/d')"
printf '  Líneas de negocio: %s\n' "$(printf '%s' "${LINEAS:-(ninguna)}" | tr '\n' ' ')"

papi GET /api/v1/service-clients >/dev/null
CLIENTES="$(jget '.[]|.clientId' <"$RESP" | sed '/^$/d')"
printf '  Credenciales:      %s\n' "$(printf '%s' "${CLIENTES:-(ninguna)}" | tr '\n' ' ')"

# ───────────────────────────────────────────────────────────────────────────── 3 · el alta
for v in "${VERTICALES[@]}"; do
  IFS='|' read -r CODE NOMBRE PREFIJO SERVICIO <<<"$v"
  head1 "3 · ${NOMBRE} (${CODE})"

  CLIENT_ID="$(envget "${PREFIJO}_CLIENT_ID")"
  if [ -z "$CLIENT_ID" ]; then
    log "  ✗ ${PREFIJO}_CLIENT_ID no está en el .env — y el compose lo exige con «:?», así que la"
    log "    pila no habría levantado. Revisá el archivo antes de seguir."
    continue
  fi
  log "  clientId del .env: ${CLIENT_ID}"

  # ── la línea de negocio
  if printf '%s\n' "$LINEAS" | grep -qx "$CODE"; then
    log "  línea '${CODE}': ya declarada"
  elif [ "$APLICA" = false ]; then
    log "  línea '${CODE}': FALTA → se declararía"
  else
    st="$(papi POST /api/v1/business-lines "$(printf '{"code":%s,"name":%s}' "$(jstr "$CODE")" "$(jstr "$NOMBRE")")")"
    case "$st" in
      200|201) log "  línea '${CODE}': declarada" ;;
      409)     log "  línea '${CODE}': ya estaba (409)" ;;
      *)       fatal "Declarar '${CODE}' respondió ${st}: $(cat "$RESP")" ;;
    esac
  fi

  # ── la credencial de servicio
  if printf '%s\n' "$CLIENTES" | grep -qx "$CLIENT_ID"; then
    # El secreto ya no se puede releer, así que re-registrar no es una opción. Lo que sí se corrige
    # en el lugar es la vertical y los alcances, **sin tocar el clientId** — que es lo que nombra la
    # configuración de este servicio y la auditoría de todo lo que hizo.
    log "  credencial '${CLIENT_ID}': ya existe"
    if [ "$APLICA" = true ]; then
      st="$(papi PUT "/api/v1/service-clients/${CLIENT_ID}/business-line" \
            "$(printf '{"businessLineCode":%s}' "$(jstr "$CODE")")")"
      if [ "$st" = "200" ] || [ "$st" = "204" ]; then
        log "    vertical → ${CODE}: ${st}"
      else
        log "    ✗ vertical → ${CODE}: HTTP ${st} — la credencial sigue registrando «de ninguna»."
        [ "$st" = "404" ] && log "      Un 404 acá suele ser una imagen de Platform anterior a esta ruta."
        FALLA_VERTICAL=1
      fi
      st="$(papi PUT "/api/v1/service-clients/${CLIENT_ID}/audiences/PimaCore.Services" \
            "$(printf '{"scopes":%s}' "$SCOPES_PIMA")")"
      log "    alcances en PimaCore.Services: HTTP ${st}"
      st="$(papi PUT "/api/v1/service-clients/${CLIENT_ID}/audiences/PimaPlatform.Services" \
            "$(printf '{"scopes":%s}' "$SCOPES_PLATFORM")")"
      log "    alcances en PimaPlatform.Services: HTTP ${st}"
      log "    ⚠ El secreto no se puede releer. Si ${PREFIJO}_CLIENT_SECRET del .env no es el de"
      log "      esta credencial, el servicio va a seguir recibiendo 401 — y el único arreglo es"
      log "      revocarla y registrar otra, por diseño."
    else
      log "    se le corregirían la vertical y los alcances, sin tocar el clientId"
    fi
    continue
  fi

  if [ "$APLICA" = false ]; then
    log "  credencial '${CLIENT_ID}': FALTA → se registraría, y su secreto iría al .env"
    continue
  fi

  cuerpo="$(printf '{"clientId":%s,"displayName":%s,"businessLineCode":%s,"grants":[{"audience":"PimaCore.Services","scopes":%s},{"audience":"PimaPlatform.Services","scopes":%s}]}' \
    "$(jstr "$CLIENT_ID")" "$(jstr "$NOMBRE")" "$(jstr "$CODE")" "$SCOPES_PIMA" "$SCOPES_PLATFORM")"
  st="$(papi POST /api/v1/service-clients "$cuerpo")"
  case "$st" in
    200|201) ;;
    *) fatal "Registrar '${CLIENT_ID}' respondió ${st}: $(cat "$RESP")" ;;
  esac

  SECRETO="$(jget .clientSecret <"$RESP")"
  : > "$RESP"
  [ -n "$SECRETO" ] && [ "$SECRETO" != "null" ] \
    || fatal "Platform registró '${CLIENT_ID}' y no devolvió secreto. Revocala y volvé a intentar."

  cp -p .env ".env.bak.$(date -u +%Y%m%dT%H%M%SZ)"
  # El secreto va al .env por el entorno de awk, que sólo ve este proceso: no pasa por stdout ni por
  # la lista de procesos.
  CLAVE="${PREFIJO}_CLIENT_SECRET" NUEVO="$SECRETO" awk '
    BEGIN { k = ENVIRON["CLAVE"]; v = ENVIRON["NUEVO"]; hecho = 0 }
    index($0, k "=") == 1 { print k "=" v; hecho = 1; next }
    { print }
    END { if (!hecho) print k "=" v }
  ' .env > .env.nuevo && mv .env.nuevo .env
  unset SECRETO
  log "  credencial '${CLIENT_ID}': registrada, y su secreto escrito en ${PREFIJO}_CLIENT_SECRET"
  log "    (queda una copia del .env anterior al lado)"

  # Y se relee, en vez de darlo por hecho. Un `businessLineCode` que Platform no entienda —porque
  # la imagen desplegada es anterior a ese campo— se descarta en silencio al deserializar: la
  # credencial queda registrada, el 201 llega igual, y todo lo que haga se anota «de ninguna
  # vertical». Es exactamente la forma silenciosa que este alta vino a cerrar, así que no se
  # supone: se vuelve a preguntar.
  papi GET /api/v1/service-clients >/dev/null
  puesta="$("$JSON_LECTOR" -c '
import sys, json
cid = sys.argv[1]
d = json.load(sys.stdin)
print(next((str(c.get("businessLineCode") or "") for c in d if c.get("clientId") == cid), ""))
' "$CLIENT_ID" <"$RESP" 2>/dev/null | tr -d '\r' || true)"
  if [ "$puesta" = "$CODE" ]; then
    log "    vertical confirmada: ${puesta}"
  else
    log "    ✗ quedó registrada SIN vertical (leído: '${puesta:-ninguna}')."
    log "      Si la imagen de Platform es anterior a este campo, actualizala y después corré:"
    log "      PUT /api/v1/service-clients/${CLIENT_ID}/business-line  {\"businessLineCode\":\"${CODE}\"}"
    log "      o ponela desde la consola, en Credenciales de servicio."
    FALLA_VERTICAL=1
  fi
done

if [ "$APLICA" = false ]; then
  head1 "nada se escribió"
  log "  Para hacerlo:  $0 aplicar"
  exit 0
fi

# ──────────────────────────────────────────────────────── 4 · reiniciar y leer qué dicen ahora
head1 "4 · reiniciar las verticales y comprobar"
SERVICIOS=()
for v in "${VERTICALES[@]}"; do IFS='|' read -r _ _ _ s <<<"$v"; SERVICIOS+=("$s"); done
$DC up -d --force-recreate "${SERVICIOS[@]}"
sleep 12

FALLA=0
for v in "${VERTICALES[@]}"; do
  IFS='|' read -r CODE NOMBRE PREFIJO SERVICIO <<<"$v"
  linea="$(linea_arranque "$SERVICIO" || true)"
  if printf '%s' "$linea" | grep -qi "confirmada"; then
    log "  ✓ ${SERVICIO}: ${linea}"
  else
    log "  ✗ ${SERVICIO}: ${linea:-sin rastro}"
    FALLA=1
  fi
done

# Dos fallas distintas, y conviene no juntarlas: un servicio que no confirma su línea está mal
# configurado y no opera; una credencial sin vertical opera perfecto y anota mal. Decir «algo
# falló» para las dos manda a buscar al lugar equivocado.
head1 "resultado"
if [ "$FALLA" = 0 ]; then
  log "  ✓ Las dos verticales confirmaron su línea contra Platform."
else
  log "  ✗ Alguna vertical no confirmó su línea: está arrancando sin poder preguntar."
  log "    Si su log dice «Falta la credencial», el secreto del .env no es el de la credencial que"
  log "    Platform tiene. No hay forma de releer un secreto: revocala y registrá otra."
fi

if [ "$FALLA_VERTICAL" = 0 ]; then
  log "  ✓ Cada credencial quedó atribuida a su vertical."
else
  log "  ✗ Alguna credencial quedó sin vertical. Funciona igual —ésa es la trampa— y todo lo que"
  log "    haga se registra «de ninguna». Se corrige desde la consola, en Credenciales de servicio,"
  log "    o con PUT /api/v1/service-clients/<clientId>/business-line."
fi

if [ "$FALLA" = 0 ] && [ "$FALLA_VERTICAL" = 0 ]; then
  log ""
  log "  Lo que esto NO hace, y falta para que una vertical opere de verdad: inscribir una empresa"
  log "  en la línea, concederle el rol de operador sobre esa participación, y que su contrato"
  log "  tenga plan. Eso es la Parte B del runbook, y es por cliente y no por vertical."
else
  exit 1
fi
