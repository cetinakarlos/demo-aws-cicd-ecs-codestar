#!/usr/bin/env bash
# ===========================================
#  ██████╗ ██████╗ ███████╗███████╗
#  ██╔══██╗██╔══██╗██╔════╝██╔════╝
#  ██████╔╝██████╔╝█████╗  █████╗
#  ██╔═══╝ ██╔═══╝ ██╔══╝  ██╔══╝
#  ██║     ██║     ███████╗███████╗
#  ╚═╝     ╚═╝     ╚══════╝╚══════╝
#  🚀 KODE-SOUL | The Future is Now! 🔥
#  Automate. Deploy. Dominate.
#  by Twinme – Terraform local state
# ===========================================

set -euo pipefail

# ---- Defaults (overridable) ----
AWS_PROFILE_DEFAULT="default" # <-- you can set anyone you have in ~/.aws/credentials
REGION_DEFAULT="us-east-1" # <-- you can set anyone you want
ENVS=("develop" "stage" "prod") # <-- predefined envs

info(){ echo -e "ℹ️  $*"; }
ok(){ echo -e "✅ $*"; }
warn(){ echo -e "⚠️  $*"; }
err(){ echo -e "❌ $*" >&2; }

AWS_PROFILE="${AWS_PROFILE_DEFAULT}"
REGION="${REGION_DEFAULT}"
while [[ "${1:-}" =~ ^- ]]; do
  case "$1" in
    --profile) AWS_PROFILE="${2}"; shift 2 ;;
    --region)  REGION="${2}"; shift 2 ;;
    -h|--help)
      cat <<EOF
Uso: $(basename "$0") [--profile PERFIL_AWS] [--region REGION]
Por defecto: --profile ${AWS_PROFILE_DEFAULT} --region ${REGION_DEFAULT}
EOF
      exit 0 ;;
    *) err "Flag no reconocido: $1"; exit 1 ;;
  esac
done

command -v terraform >/dev/null || { err "Terraform no encontrado"; exit 1; }
command -v aws >/dev/null || { err "AWS CLI no encontrado"; exit 1; }
if ! command -v dot >/dev/null; then
  warn "graphviz (dot) no instalado: la opción 7 no funcionará."
fi

# ...
echo "# ==========================================="
echo "#  🚀 Script Terraform local por entorno (sin backend remoto)"
echo "# ==========================================="
echo "Selecciona el entorno:"
select ENV in "${ENVS[@]}" "Salir"; do
  case "${ENV:-}" in
    develop|stage|prod)
      break
      ;;
    Salir)
      echo "👋 Saliendo..."
      exit 0
      ;;
    *)
      err "Opción no válida"
      ;;
  esac
done


export AWS_PROFILE AWS_REGION="${REGION}" AWS_DEFAULT_REGION="${REGION}"
ok "Usando AWS_PROFILE=${AWS_PROFILE} | REGION=${REGION}"

WORKDIR="./"
[[ -d "${WORKDIR}" ]] || { err "No existe ${WORKDIR}"; exit 1; }
cd "${WORKDIR}"

TFVARS="${ENV}.tfvars"
[[ -f "${TFVARS}" ]] || { err "Falta ${TFVARS}"; exit 1; }

tf_init_plan () {
  info "Formateando..."
  terraform fmt -recursive || true

  # init simple, local backend by default
  info "Init (local state)…"
  terraform init -input=false

  ok "Validate…"
  terraform validate

  info "Plan (${TFVARS})…"
  terraform plan -var-file="${TFVARS}"
}

tf_apply () {
  warn "Aplicar cambios en [$ENV] (state local en $(pwd)/terraform.tfstate)"
  read -r -p "Escribe APPLY para continuar: " C; [[ "$C" == "APPLY" ]] || { err "Cancelado."; return 1; }
  terraform apply -auto-approve -var-file="${TFVARS}"
  ok "Apply completado."
}

tf_destroy () {
  warn "¡DESTRUCTIVO! Destruir [$ENV] (state local)"
  read -r -p "Escribe DESTROY para confirmar: " C; [[ "$C" == "DESTROY" ]] || { err "Cancelado."; return 1; }
  terraform destroy -auto-approve -var-file="${TFVARS}"
  ok "Destroy completado."
}

tf_graph () {
  local OUTDIR="docs/diagrams"
  local OUTPNG="${OUTDIR}/tf-graph.png"
  mkdir -p "${OUTDIR}"
  if command -v dot >/dev/null; then
    terraform graph | dot -Tpng > "${OUTPNG}"
    ok "Diagrama generado en ${OUTPNG}"
  else
    err "graphviz (dot) no instalado."
  fi
}

while true; do
  echo "----------------------------"
  echo "Entorno: ${ENV} | Perfil: ${AWS_PROFILE} | Región: ${REGION}"
  echo "1) Init + Validate + Plan"
  echo "2) Apply"
  echo "3) Validate (rápido)"
  echo "7) Generar diagrama (terraform graph)"
  echo "8) 🚨 Destroy"
  echo "9) Fmt + Validate"
  echo "5) Salir"
  echo "----------------------------"
  read -r -p "👉 Opción: " op
  case "${op}" in
    1) tf_init_plan ;;
    2) tf_apply ;;
    3) terraform init -input=false -reconfigure && terraform validate ;;
    7) tf_graph ;;
    8) tf_destroy ;;
    9) terraform fmt -recursive && terraform validate ;;
    5) echo "Listo, Kode-Soul. ¡Fiera!"; exit 0 ;;
    *) err "Opción no válida." ;;
  esac
done
