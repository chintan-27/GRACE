#!/usr/bin/env bash
#====================================================================
# GRACE Training Script - Single File, Improved UX
# - Simpler flags
# - No --background (user can use nohup/& themselves)
# - Predictable data mounts (/mnt/data inside containers)
# - No brittle 'sed' command mutations; build args once from variables
# ====================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# ====================================================================
# USER CONFIGURATION - Edit these defaults as needed
# ====================================================================

# ---- Training arg defaults (parsed into ARG_* and rebuilt) ----
ARG_NUM_GPU=1
ARG_DATA_DIR="./data_folder/"
ARG_MODEL_NAME="grace"
ARG_N_CLASSES=12
ARG_MAX_ITER=1000
ARG_A_MIN=0
ARG_A_MAX=255

# ---- Docker settings ----
DOCKER_IMAGE="grace:latest"
DOCKER_WORKSPACE="/workspace"
DOCKER_BASE_IMAGE="projectmonai/monai:1.5.0"

# ---- Singularity settings ----
SINGULARITY_CONTAINER=""                # Set to existing sandbox/image path to reuse
SINGULARITY_AUTOBUILD=true              # If empty above, build a sandbox from the MONAI docker image
SINGULARITY_REPO_MOUNT="/workspace"
SINGULARITY_DATA_MOUNT="/mnt/data"
SINGULARITY_BIND_EXTRA=""               # e.g., "/scratch:/scratch"

# ---- Python (native) settings ----
PYTHON_FILE="train.py"                  # entrypoint expected in repo root

# ---- Control flags ----
ALLOW_CPU_FALLBACK=false
REQUIRE_GPU=false
REBUILD_DOCKER=false

# ---- Logging ----
LOG_FILE=""                             # e.g., "--log-file run_$(date +%F_%H%M).log"

# ====================================================================
# LOGGING HELPERS
# ====================================================================

log()   { echo "[$(date '+%H:%M:%S')] $*"; }
warn()  { echo "[$(date '+%H:%M:%S')] WARN: $*" >&2; }
err()   { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

run_with_logging() {
  # usage: run_with_logging "<command string>"
  if [[ -n "${LOG_FILE}" ]]; then
    bash -lc "$1" 2>&1 | tee -a "${LOG_FILE}"
  else
    bash -lc "$1"
  fi
}

# ====================================================================
# ENVIRONMENT HELPERS
# ====================================================================

have() { command -v "$1" >/dev/null 2>&1; }

# Built commands (rebuilt after parsing)
PYTHON_COMMAND=""         # for containers (always uses /mnt/data)
PYTHON_LOCAL_COMMAND=""   # for native (uses LOCAL_DATA_DIR)
LOCAL_DATA_DIR=""         # absolute host path

# ====================================================================
# USAGE
# ====================================================================

print_usage() {
  cat <<EOF
Usage: $0 [ENVIRONMENT] [OPTIONS]

ENVIRONMENT (choose one):
  --docker         Use Docker container
  --singularity    Use Singularity container
  --python         Use native Python environment

Training options:
  --data_dir PATH            Path to data folder (default: ./data_folder/)
  --num_gpu NUM              Number of GPUs (default: 1)
  --N_classes NUM            Number of classes (default: 12)
  --max_iteration NUM        Max iterations (default: 1000)
  --model_save_name NAME     Model save name (default: grace)
  --a_min_value NUM          Min intensity value (default: 0)
  --a_max_value NUM          Max intensity value (default: 255)

Control:
  --rebuild-docker           Force rebuild Docker image (Docker only)
  --allow-cpu                Allow CPU-only training if GPU unavailable
  --require-gpu              Require GPU (fail if not available)
  --log-file FILE            Also save console output to FILE
  --help                     Show this help

Quickstarts:
  Docker:      $0 --docker --data_dir /absolute/path/to/data
  Singularity: $0 --singularity --data_dir /absolute/path/to/data
  Python:      $0 --python --data_dir ./data_folder

Notes:
- Inside containers your data will appear at /mnt/data.
- For running in the background use 'nohup' or '&' if desired:
    nohup $0 --docker --data_dir /data > run.log 2>&1 &
EOF
}

# ====================================================================
# ARG PARSING (no sed; set variables and rebuild commands once)
# ====================================================================

ENVIRONMENT=""

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --docker)      ENVIRONMENT="docker"; shift;;
      --singularity) ENVIRONMENT="singularity"; shift;;
      --python)      ENVIRONMENT="python"; shift;;
      --rebuild-docker) REBUILD_DOCKER=true; shift;;
      --allow-cpu)   ALLOW_CPU_FALLBACK=true; shift;;
      --require-gpu) REQUIRE_GPU=true; ALLOW_CPU_FALLBACK=false; shift;;
      --data_dir)    ARG_DATA_DIR="$2"; shift 2;;
      --num_gpu)     ARG_NUM_GPU="$2"; shift 2;;
      --N_classes)   ARG_N_CLASSES="$2"; shift 2;;
      --max_iteration) ARG_MAX_ITER="$2"; shift 2;;
      --model_save_name) ARG_MODEL_NAME="$2"; shift 2;;
      --a_min_value) ARG_A_MIN="$2"; shift 2;;
      --a_max_value) ARG_A_MAX="$2"; shift 2;;
      --log-file)    LOG_FILE="$2"; shift 2;;
      --help|-h)     print_usage; exit 0;;
      *) err "Unknown option: $1 (use --help)";;
    esac
  done

  if [[ -z "${ENVIRONMENT}" ]]; then
    err "Please specify an environment: --docker, --singularity, or --python"
  fi

  # Canonicalize LOCAL_DATA_DIR to absolute path
  if [[ -z "${ARG_DATA_DIR}" ]]; then
    err "--data_dir is required (or set default ./data_folder/)"
  fi
  if [[ "${ARG_DATA_DIR}" = /* ]]; then
    LOCAL_DATA_DIR="${ARG_DATA_DIR}"
  else
    LOCAL_DATA_DIR="$(cd "$(dirname "${ARG_DATA_DIR}")" && pwd)/$(basename "${ARG_DATA_DIR}")"
  fi

  # Build final commands (container vs local)
  local CONTAINER_DATA_DIR="/mnt/data"
  PYTHON_COMMAND="python3 /workspace/train.py \
    --num_gpu ${ARG_NUM_GPU} \
    --data_dir ${CONTAINER_DATA_DIR} \
    --model_save_name ${ARG_MODEL_NAME} \
    --N_classes ${ARG_N_CLASSES} \
    --max_iteration ${ARG_MAX_ITER} \
    --a_min_value ${ARG_A_MIN} \
    --a_max_value ${ARG_A_MAX}"

  PYTHON_LOCAL_COMMAND="python3 ${PYTHON_FILE} \
    --num_gpu ${ARG_NUM_GPU} \
    --data_dir \"${LOCAL_DATA_DIR}\" \
    --model_save_name ${ARG_MODEL_NAME} \
    --N_classes ${ARG_N_CLASSES} \
    --max_iteration ${ARG_MAX_ITER} \
    --a_min_value ${ARG_A_MIN} \
    --a_max_value ${ARG_A_MAX}"
}

# ====================================================================
# VALIDATION & SUMMARY
# ====================================================================

validate_configuration() {
  # Conflicting flags
  if [[ "${REQUIRE_GPU}" == true && "${ALLOW_CPU_FALLBACK}" == true ]]; then
    err "Cannot use both --require-gpu and --allow-cpu"
  fi
  if [[ "${REQUIRE_GPU}" == true && "${ARG_NUM_GPU}" -le 0 ]]; then
    err "--require-gpu set but --num_gpu is ${ARG_NUM_GPU}"
  fi

  # Repo file present?
  if [[ ! -f "${PYTHON_FILE}" ]]; then
    err "Expected ${PYTHON_FILE} in current directory: $(pwd)"
  fi

  # Data dir exists?
  if [[ ! -d "${LOCAL_DATA_DIR}" ]]; then
    err "Data directory not found: ${LOCAL_DATA_DIR}"
  fi

  # Singularity bind format hint (only if user set extra)
  if [[ -n "${SINGULARITY_BIND_EXTRA}" && "${SINGULARITY_BIND_EXTRA}" != *:* ]]; then
    err "SINGULARITY_BIND_EXTRA must be 'host_path:container_path' (got: ${SINGULARITY_BIND_EXTRA})"
  fi
}

print_configuration() {
  log "======================================================================"
  log "GRACE Training"
  log "Environment: ${ENVIRONMENT}"
  log "GPU required: ${REQUIRE_GPU} | CPU fallback: ${ALLOW_CPU_FALLBACK}"
  if [[ -n "${LOG_FILE}" ]]; then log "Log file: ${LOG_FILE}"; fi
  log "Data (host): ${LOCAL_DATA_DIR}"
  log "Args: num_gpu=${ARG_NUM_GPU} N_classes=${ARG_N_CLASSES} max_iter=${ARG_MAX_ITER}"
  log "Model: ${ARG_MODEL_NAME} | a_min=${ARG_A_MIN} | a_max=${ARG_A_MAX}"
  if [[ "${ENVIRONMENT}" = "docker" ]]; then
    log "Docker image: ${DOCKER_IMAGE} (base: ${DOCKER_BASE_IMAGE})"
  elif [[ "${ENVIRONMENT}" = "singularity" ]]; then
    log "Singularity container: ${SINGULARITY_CONTAINER:-<auto-build if empty>}"
  fi
  log "======================================================================"
}

# ====================================================================
# GPU HANDLING
# ====================================================================

handle_gpu_unavailable() {
  local reason="$1"
  warn "GPU unavailable: ${reason}"
  if [[ "${REQUIRE_GPU}" == true ]]; then
    err "GPU required but not available. Aborting."
  fi
  if [[ "${ALLOW_CPU_FALLBACK}" == true ]]; then
    warn "Continuing with CPU-only training (slower)"
    ARG_NUM_GPU=0
    # Rebuild commands with num_gpu=0
    parse_arguments_post_gpu_fix
  else
    err "GPU not available and CPU fallback not enabled. Use --allow-cpu if intentional."
  fi
}

# Rebuild commands after changing ARG_NUM_GPU
parse_arguments_post_gpu_fix() {
  local CONTAINER_DATA_DIR="/mnt/data"
  PYTHON_COMMAND="python3 /workspace/train.py \
    --num_gpu ${ARG_NUM_GPU} \
    --data_dir ${CONTAINER_DATA_DIR} \
    --model_save_name ${ARG_MODEL_NAME} \
    --N_classes ${ARG_N_CLASSES} \
    --max_iteration ${ARG_MAX_ITER} \
    --a_min_value ${ARG_A_MIN} \
    --a_max_value ${ARG_A_MAX}"

  PYTHON_LOCAL_COMMAND="python3 ${PYTHON_FILE} \
    --num_gpu ${ARG_NUM_GPU} \
    --data_dir \"${LOCAL_DATA_DIR}\" \
    --model_save_name ${ARG_MODEL_NAME} \
    --N_classes ${ARG_N_CLASSES} \
    --max_iteration ${ARG_MAX_ITER} \
    --a_min_value ${ARG_A_MIN} \
    --a_max_value ${ARG_A_MAX}"
}

# ====================================================================
# DOCKER
# ====================================================================

create_dockerfile() {
  log "Creating Dockerfile (base: ${DOCKER_BASE_IMAGE})..."
  cat > Dockerfile <<EOF
# GRACE Docker Image - Auto-generated
FROM ${DOCKER_BASE_IMAGE}
WORKDIR ${DOCKER_WORKSPACE}
RUN apt-get update && apt-get install -y \\
    git \\
    wget \\
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir \\
    nibabel \\
    scikit-learn \\
    tqdm \\
    numpy \\
    matplotlib \\
    scipy
COPY . ${DOCKER_WORKSPACE}/
CMD ["bash"]
EOF
}

build_docker_image() {
  log "Building Docker image: ${DOCKER_IMAGE}"
  [[ -f Dockerfile ]] || create_dockerfile
  docker build -t "${DOCKER_IMAGE}" .
  log "Docker image built: ${DOCKER_IMAGE}"
  # smoke test
  docker run --rm "${DOCKER_IMAGE}" python3 -c "import torch, monai; print('Image OK')" >/dev/null 2>&1 || \
    warn "Image test failed (torch/monai import). Training may hit deps issues."
}

test_docker_gpu_access() {
  if [[ "${ARG_NUM_GPU}" -le 0 ]]; then
    log "GPU not requested (num_gpu=${ARG_NUM_GPU}); skipping Docker GPU test."
    return
  fi
  if ! docker run --help | grep -q -- '--gpus'; then
    handle_gpu_unavailable "Docker lacks --gpus support"
    return
  fi
  log "Checking CUDA in Docker container..."
  local out
  if ! out=$(docker run --rm --gpus all "${DOCKER_IMAGE}" python3 - <<'PY' 2>/dev/null
import torch, sys
try:
    print("CUDA_AVAILABLE:", torch.cuda.is_available())
    print("GPU_COUNT:", torch.cuda.device_count())
    for i in range(torch.cuda.device_count()):
        print(f"GPU_{i}:", torch.cuda.get_device_name(i))
except Exception as e:
    print("ERROR:", e)
    sys.exit(1)
PY
  ); then
    warn "Docker GPU test command failed."
    handle_gpu_unavailable "Docker GPU test failed"
    return
  fi
  if echo "$out" | grep -q "CUDA_AVAILABLE: True"; then
    log "GPU support verified in Docker:"
    echo "$out" | grep -E 'GPU_COUNT:|GPU_[0-9]:' || true
  else
    handle_gpu_unavailable "No CUDA GPUs detected in Docker"
  fi
}

docker_train() {
  have docker || err "docker not found."
  docker info >/dev/null 2>&1 || err "Docker daemon not running."

  if [[ "${REBUILD_DOCKER}" == true ]]; then
    log "Rebuilding Docker image on request (--rebuild-docker)"
    docker rmi "${DOCKER_IMAGE}" >/dev/null 2>&1 || true
  fi

  if ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
    log "Docker image '${DOCKER_IMAGE}' not found; building…"
    build_docker_image
  fi

  test_docker_gpu_access

  # Only pass --gpus all if GPUs are requested and supported
  local docker_gpu_flag=()
  if [[ "${ARG_NUM_GPU}" -gt 0 ]] && docker run --help | grep -q -- '--gpus'; then
    docker_gpu_flag=(--gpus all)
  fi

  local cmd="docker run --rm -it \
    ${docker_gpu_flag[*]} \
    --shm-size=16g \
    --ipc=host \
    -v \"$(pwd):${DOCKER_WORKSPACE}\" \
    -v \"${LOCAL_DATA_DIR}:/mnt/data:ro\" \
    -w \"${DOCKER_WORKSPACE}\" \
    -e HOME=\"${DOCKER_WORKSPACE}\" \
    --user \"$(id -u):$(id -g)\" \
    \"${DOCKER_IMAGE}\" \
    bash -lc \"${PYTHON_COMMAND}\""

  log "Running GRACE training in Docker…"
  run_with_logging "${cmd}"
}

# ====================================================================
# SINGULARITY
# ====================================================================

test_singularity_cuda() {
  if [[ "${ARG_NUM_GPU}" -le 0 ]]; then
    log "GPU not requested (num_gpu=${ARG_NUM_GPU}); skipping Singularity CUDA test."
    return
  fi
  log "Checking CUDA in Singularity container…"
  if singularity exec --nv "${SINGULARITY_CONTAINER}" python3 - <<'PY' 2>/dev/null | grep -q True; then
import torch
print(torch.cuda.is_available())
PY
    log "CUDA support verified in Singularity."
  else
    handle_gpu_unavailable "CUDA check failed in Singularity container"
  fi
}

build_singularity_container() {
  [[ -n "${SINGULARITY_CONTAINER}" ]] || SINGULARITY_CONTAINER="./monai_sandbox"
  log "Building Singularity sandbox at ${SINGULARITY_CONTAINER} from docker://${DOCKER_BASE_IMAGE}…"
  singularity build --sandbox "${SINGULARITY_CONTAINER}" "docker://${DOCKER_BASE_IMAGE}"
  log "Singularity container ready: ${SINGULARITY_CONTAINER}"
}

singularity_train() {
  have singularity || err "singularity not found."

  if [[ -z "${SINGULARITY_CONTAINER}" ]]; then
    if [[ "${SINGULARITY_AUTOBUILD}" == true ]]; then
      build_singularity_container
    else
      err "Set SINGULARITY_CONTAINER or enable SINGULARITY_AUTOBUILD=true"
    fi
  elif [[ ! -d "${SINGULARITY_CONTAINER}" && ! -f "${SINGULARITY_CONTAINER}" ]]; then
    if [[ "${SINGULARITY_AUTOBUILD}" == true ]]; then
      build_singularity_container
    else
      err "Singularity container not found at ${SINGULARITY_CONTAINER}"
    fi
  fi

  test_singularity_cuda

  # --nv only if GPU requested
  local nv_flag=()
  if [[ "${ARG_NUM_GPU}" -gt 0 ]]; then nv_flag=(--nv); fi

  # Build binds
  local binds=( "--bind" "$(pwd):${SINGULARITY_REPO_MOUNT}" "--bind" "${LOCAL_DATA_DIR}:${SINGULARITY_DATA_MOUNT}:ro" )
  if [[ -n "${SINGULARITY_BIND_EXTRA}" ]]; then
    binds+=( "--bind" "${SINGULARITY_BIND_EXTRA}" )
  fi

  local cmd="singularity exec ${nv_flag[*]} ${binds[*]} \
    \"${SINGULARITY_CONTAINER}\" \
    bash -lc \"cd ${SINGULARITY_REPO_MOUNT} && ${PYTHON_COMMAND}\""

  log "Running GRACE training in Singularity…"
  run_with_logging "${cmd}"
}

# ====================================================================
# PYTHON (NATIVE)
# ====================================================================

detect_and_setup_python_env() {
  # Make 'conda activate' work in non-interactive shells
  if have conda; then
    eval "$(conda shell.bash hook)" || true
    # Prefer existing 'grace' env if present
    if conda env list | awk '{print $1}' | grep -qx grace; then
      log "Using conda environment: grace"
      conda activate grace || true
    fi
  fi
}

check_and_install_dependencies() {
  log "Checking Python dependencies (torch, torchvision, monai, numpy, nibabel)…"
  local deps_ok=true
  python - <<'PY' || deps_ok=false
mods = ["torch", "torchvision", "monai", "numpy", "nibabel"]
missing = []
for m in mods:
    try:
        __import__(m)
    except Exception:
        missing.append(m)
if missing:
    print("MISSING:", ",".join(missing))
else:
    print("OK")
PY

  if [[ "${deps_ok}" = false ]]; then
    if [[ -f "requirements.txt" ]]; then
      log "Installing from requirements.txt…"
      run_with_logging "pip install -r requirements.txt"
    else
      log "Installing missing core packages…"
      # Try CUDA wheels if available; otherwise default
      if ! python -c 'import torch' >/dev/null 2>&1; then
        run_with_logging "pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118 || pip install torch torchvision"
      fi
      run_with_logging "pip install monai numpy nibabel"
    fi
  else
    log "Dependencies present."
  fi
}

check_python_gpu_availability() {
  log "Checking GPU availability in native Python…"
  local out
  out=$(python - <<'PY' 2>/dev/null || true
import torch
print("CUDA available:", torch.cuda.is_available())
print("GPU count:", torch.cuda.device_count() if torch.cuda.is_available() else 0)
if torch.cuda.is_available():
    print("GPU 0:", torch.cuda.get_device_name(0))
PY
  )
  log "$out"
  if echo "$out" | grep -q "CUDA available: False"; then
    handle_gpu_unavailable "No CUDA GPU detected in native Python"
  fi
}

python_train() {
  detect_and_setup_python_env
  check_and_install_dependencies
  if [[ "${ARG_NUM_GPU}" -gt 0 ]]; then
    check_python_gpu_availability
  fi
  local cmd="${PYTHON_LOCAL_COMMAND}"
  log "Running GRACE training (native Python)…"
  run_with_logging "${cmd}"
}

# ====================================================================
# MAIN
# ====================================================================

cleanup_on_exit() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    err "Training failed with exit code $code"
  fi
  exit $code
}

trap cleanup_on_exit EXIT

main() {
  parse_arguments "$@"
  validate_configuration
  print_configuration
  case "${ENVIRONMENT}" in
    docker)      docker_train ;;
    singularity) singularity_train ;;
    python)      python_train ;;
    *) err "Invalid environment: ${ENVIRONMENT}" ;;
  esac
  log "Training completed successfully!"
}

main "$@"