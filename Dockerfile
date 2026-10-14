# ─── Etapa 1: builder ────────────────────────────────────────────────────────
# Instala uv y las dependencias de producción en un venv aislado
FROM python:3.12-slim AS builder

# Instalar uv desde su imagen oficial (versión fijada)
COPY --from=ghcr.io/astral-sh/uv:0.6.14 /uv /usr/local/bin/uv

WORKDIR /build

# Copiar solo los archivos de dependencias para aprovechar la caché de capas
COPY pyproject.toml uv.lock ./

# Instalar dependencias de producción (sin dev) con versiones exactas del lockfile
# UV_PROJECT_ENVIRONMENT indica dónde crea el venv
RUN uv sync --no-dev --frozen --project . --python python3.12

# ─── Etapa 2: imagen final ────────────────────────────────────────────────────
FROM python:3.12-slim AS final

# Crear usuario y grupo no-root; el home será el directorio de trabajo
RUN groupadd --gid 1001 app && \
    useradd --uid 1001 --gid app --shell /bin/sh --create-home app

WORKDIR /srv/reservas

# Copiar el venv construido en la etapa anterior (solo deps de producción, sin uv)
COPY --from=builder /build/.venv /srv/reservas/.venv

# Copiar únicamente el paquete de la aplicación
COPY reservas/ /srv/reservas/reservas/

# Asegurar que el usuario app sea dueño del directorio de trabajo
# (necesario para que pueda crear instancia/reservas.db en modo SQLite)
RUN chown -R app:app /srv/reservas

# Cambiar al usuario no-root
USER app

# Exponer el puerto de la aplicación
EXPOSE 8500

# Verificación de salud: consulta /estado cada 10 s, 5 reintentos, 30 s de margen inicial
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
    CMD /srv/reservas/.venv/bin/python -c \
        "import urllib.request, sys; \
         r = urllib.request.urlopen('http://localhost:8500/estado', timeout=4); \
         sys.exit(0 if r.status == 200 else 1)"

# Arrancar uvicorn en forma exec (PID 1) usando python -m para evitar shebangs rotos del venv copiado
CMD ["/srv/reservas/.venv/bin/python", "-m", "uvicorn", "reservas.api:app", \
     "--host", "0.0.0.0", "--port", "8500"]
