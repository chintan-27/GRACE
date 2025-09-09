#!/bin/bash

# GRACE Data Processing Setup Script with Virtual Environment
# This script sets up a virtual environment and processes GRACE data

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Virtual environment settings
VENV_NAME="grace_env"
VENV_PATH="./$VENV_NAME"

# Default values
DEFAULT_DATA_DIR="GRACE_Data"
DEFAULT_SPLIT_RATIO="0.9"
DEFAULT_RANDOM_SEED="42"

# Global variables for parameters
DATA_DIR=""
SPLIT_RATIO=""
RANDOM_SEED=""

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -d, --data-dir DIR       Data directory containing images/ and labels/ folders"
    echo "                          (default: $DEFAULT_DATA_DIR)"
    echo "  -s, --split-ratio RATIO  Train/test split ratio (0.0-1.0)"
    echo "                          (default: $DEFAULT_SPLIT_RATIO, means 90% train, 10% test)"
    echo "  -r, --random-seed SEED   Random seed for reproducibility"
    echo "                          (default: $DEFAULT_RANDOM_SEED)"
    echo "  -h, --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                          # Use all defaults"
    echo "  $0 -d /path/to/data                        # Custom data directory"
    echo "  $0 -d ./my_data -s 0.8 -r 123             # Custom parameters"
    echo "  $0 --data-dir ./data --split-ratio 0.85    # Long options"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--data-dir)
                DATA_DIR="$2"
                shift 2
                ;;
            -s|--split-ratio)
                SPLIT_RATIO="$2"
                shift 2
                ;;
            -r|--random-seed)
                RANDOM_SEED="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults if not provided
    DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
    SPLIT_RATIO="${SPLIT_RATIO:-$DEFAULT_SPLIT_RATIO}"
    RANDOM_SEED="${RANDOM_SEED:-$DEFAULT_RANDOM_SEED}"
}

# Validate parameters
validate_parameters() {
    log "Validating parameters..."
    
    # Validate data directory
    if [ ! -d "$DATA_DIR" ]; then
        error "Data directory does not exist: $DATA_DIR"
        exit 1
    fi
    
    # Validate split ratio
    if ! python3 -c "
import sys
try:
    ratio = float('$SPLIT_RATIO')
    if not (0.0 < ratio < 1.0):
        sys.exit(1)
except ValueError:
    sys.exit(1)
" 2>/dev/null; then
        error "Split ratio must be a number between 0.0 and 1.0, got: $SPLIT_RATIO"
        exit 1
    fi
    
    # Validate random seed
    if ! [[ "$RANDOM_SEED" =~ ^[0-9]+$ ]]; then
        error "Random seed must be a positive integer, got: $RANDOM_SEED"
        exit 1
    fi
    
    log "Parameters validated:"
    log "  📁 Data directory: $DATA_DIR"
    log "  📊 Split ratio: $SPLIT_RATIO ($(python3 -c "print(f'{float('$SPLIT_RATIO')*100:.1f}%')") train)"
    log "  🎲 Random seed: $RANDOM_SEED"
    
    success "Parameter validation passed"
}

# Print header
print_header() {
    echo "=========================================================================="
    echo "                    GRACE Data Processing Setup (venv)"
    echo "=========================================================================="
    echo "Configuration:"
    echo "  📁 Data Directory: $DATA_DIR"
    echo "  📊 Split Ratio: $SPLIT_RATIO"
    echo "  🎲 Random Seed: $RANDOM_SEED"
    echo
    echo "This script will:"
    echo "  1. Check Python environment"
    echo "  2. Create virtual environment: $VENV_NAME"
    echo "  3. Install required packages (scikit-learn, tqdm)"
    echo "  4. Split data into train/test sets"
    echo "  5. Create dataset.json for training"
    echo "  6. Cleanup virtual environment"
    echo "=========================================================================="
    echo
}

# Check if Python is installed
check_python() {
    log "Checking Python installation..."
    
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        log "Found Python3: $(python3 --version)"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
        log "Found Python: $(python --version)"
    else
        error "Python is not installed. Please install Python 3.6 or higher."
        exit 1
    fi
    
    # Check Python version
    PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    log "Python version: $PYTHON_VERSION"
    
    if (( $(echo "$PYTHON_VERSION < 3.6" | bc -l) 2>/dev/null || [ "$PYTHON_VERSION" \< "3.6" ] )); then
        error "Python 3.6 or higher is required. Found: $PYTHON_VERSION"
        exit 1
    fi
    
    success "Python check passed"
}

# Check if venv module is available
check_venv() {
    log "Checking venv module availability..."
    
    if $PYTHON_CMD -m venv --help &> /dev/null; then
        success "venv module is available"
    else
        error "venv module is not available."
        echo "Please install python3-venv:"
        echo "  Ubuntu/Debian: sudo apt-get install python3-venv"
        echo "  CentOS/RHEL: sudo yum install python3-venv"
        echo "  macOS: venv should be included with Python 3.3+"
        exit 1
    fi
}

# Create virtual environment
create_venv() {
    log "Creating virtual environment: $VENV_NAME"
    
    if [ -d "$VENV_PATH" ]; then
        log "Removing existing virtual environment..."
        rm -rf "$VENV_PATH"
    fi
    
    log "Creating new virtual environment..."
    $PYTHON_CMD -m venv "$VENV_PATH"
    
    if [ -d "$VENV_PATH" ]; then
        success "Virtual environment created successfully"
    else
        error "Failed to create virtual environment"
        exit 1
    fi
}

# Activate virtual environment
activate_venv() {
    log "Activating virtual environment..."
    
    # Check which activation script exists
    if [ -f "$VENV_PATH/bin/activate" ]; then
        # Unix/Linux/macOS
        ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"
        PYTHON_VENV="$VENV_PATH/bin/python"
        PIP_VENV="$VENV_PATH/bin/pip"
    elif [ -f "$VENV_PATH/Scripts/activate" ]; then
        # Windows (Git Bash/MSYS)
        ACTIVATE_SCRIPT="$VENV_PATH/Scripts/activate"
        PYTHON_VENV="$VENV_PATH/Scripts/python"
        PIP_VENV="$VENV_PATH/Scripts/pip"
    else
        error "Cannot find activation script in virtual environment"
        exit 1
    fi
    
    # Source the activation script
    source "$ACTIVATE_SCRIPT"
    
    # Verify activation by checking python path
    CURRENT_PYTHON=$(which python 2>/dev/null || echo "not found")
    if [[ "$CURRENT_PYTHON" == *"$VENV_NAME"* ]]; then
        success "Virtual environment activated successfully"
        log "Python path: $CURRENT_PYTHON"
    else
        warning "Virtual environment activation may have failed"
        log "Current Python: $CURRENT_PYTHON"
        # Fallback to direct paths
        PYTHON_CMD="$PYTHON_VENV"
        PIP_CMD="$PIP_VENV"
    fi
}

# Upgrade pip in virtual environment
upgrade_pip() {
    log "Upgrading pip in virtual environment..."
    
    $PYTHON_VENV -m pip install --upgrade pip --quiet
    
    if [ $? -eq 0 ]; then
        success "Pip upgraded successfully"
        log "Pip version: $($PIP_VENV --version)"
    else
        warning "Pip upgrade failed, continuing with existing version"
    fi
}

# Install required packages in virtual environment
install_packages() {
    log "Installing required Python packages in virtual environment..."
    
    # List of required packages with versions for stability
    PACKAGES=(
        "scikit-learn"
        "tqdm" 
        "numpy"
    )
    
    # Install packages
    log "Installing packages..."
    for package in "${PACKAGES[@]}"; do
        log "Installing $package..."
        $PIP_VENV install "$package" --quiet
    done
    
    if [ $? -eq 0 ]; then
        success "All packages installed successfully"
    else
        error "Package installation failed"
        exit 1
    fi
    
    # Verify installations
    log "Verifying package installations..."
    for package in "sklearn" "tqdm" "numpy"; do
        if $PYTHON_VENV -c "import $package" &> /dev/null; then
            success "$package is available"
        else
            error "$package installation verification failed"
            exit 1
        fi
    done
}

# Check if required directories exist
check_directories() {
    log "Checking required directories..."
    
    REQUIRED_DIRS=("$DATA_DIR/images" "$DATA_DIR/labels")
    
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            error "Required directory not found: $dir"
            echo "Please ensure you have the following structure:"
            echo "  $DATA_DIR/"
            echo "  ├── images/     (containing .nii files)"
            echo "  └── labels/     (containing .nii files)"
            exit 1
        else
            # Count files in directory
            FILE_COUNT=$(find "$dir" -name "*.nii" | wc -l)
            log "Found $FILE_COUNT .nii files in $dir"
            
            if [ $FILE_COUNT -eq 0 ]; then
                warning "No .nii files found in $dir"
            fi
        fi
    done
    
    success "Directory structure validated"
}

# Check if required Python scripts exist
check_scripts() {
    log "Checking required Python scripts..."
    
    REQUIRED_SCRIPTS=("data_split.py" "create_dataset.py")
    
    for script in "${REQUIRED_SCRIPTS[@]}"; do
        if [ ! -f "$script" ]; then
            error "Required script not found: $script"
            exit 1
        else
            success "Found script: $script"
        fi
    done
}

# Run data splitting script
run_data_split() {
    log "Running data splitting script..."
    
    log "Executing data split with parameters:"
    log "  Base directory: $DATA_DIR"
    log "  Split ratio: $SPLIT_RATIO"
    log "  Random seed: $RANDOM_SEED"
    
    $PYTHON_VENV data_split.py --base-dir "$DATA_DIR" --split-ratio "$SPLIT_RATIO" --random-seed "$RANDOM_SEED"
    
    if [ $? -eq 0 ]; then
        success "Data splitting completed successfully"
    else
        error "Data splitting failed"
        exit 1
    fi
}

# Run dataset creation script
run_dataset_creation() {
    log "Running dataset JSON creation script..."
    
    # Check if split directories exist
    SPLIT_DIRS=("imagesTr" "labelsTr" "imagesTs")
    for dir in "${SPLIT_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            error "Split directory not found: $dir"
            error "Please run data splitting first"
            exit 1
        fi
    done
    
    log "Executing dataset creation with base directory: $DATA_DIR"
    $PYTHON_VENV create_dataset.py --base-dir "$DATA_DIR"
    
    if [ $? -eq 0 ]; then
        success "Dataset JSON creation completed successfully"
    else
        error "Dataset JSON creation failed"
        exit 1
    fi
}

# Verify output files
verify_output() {
    log "Verifying output files..."
    
    # Check if dataset.json was created
    if [ -f "dataset.json" ]; then
        FILE_SIZE=$(stat -f%z "dataset.json" 2>/dev/null || stat -c%s "dataset.json" 2>/dev/null)
        success "dataset.json created successfully (${FILE_SIZE} bytes)"
        
        # Validate JSON structure
        if $PYTHON_VENV -c "import json; json.load(open('dataset.json'))" &> /dev/null; then
            success "dataset.json is valid JSON"
        else
            warning "dataset.json may have formatting issues"
        fi
    else
        error "dataset.json was not created"
        exit 1
    fi
    
    # Check split directories and count files
    log "Output directory summary:"
    for dir in imagesTr labelsTr imagesTs labelsTs; do
        if [ -d "$dir" ]; then
            COUNT=$(find "$dir" -name "*.nii" | wc -l)
            log "  $dir: $COUNT files"
        fi
    done
}

# Cleanup virtual environment
cleanup_venv() {
    log "Cleaning up virtual environment..."
    
    # Deactivate if active
    if [[ "$VIRTUAL_ENV" != "" ]]; then
        deactivate || true
        log "Virtual environment deactivated"
    fi
    
    # Remove virtual environment directory
    if [ -d "$VENV_PATH" ]; then
        rm -rf "$VENV_PATH"
        success "Virtual environment removed: $VENV_PATH"
    else
        log "Virtual environment directory not found: $VENV_PATH"
    fi
    
    # Remove any temporary files
    [ -f "requirements.txt" ] && rm -f "requirements.txt"
    [ -f "activate_grace_env.sh" ] && rm -f "activate_grace_env.sh"
    
    success "Cleanup completed"
}

# Print final summary
print_summary() {
    echo
    echo "=========================================================================="
    echo "                           SETUP COMPLETE"
    echo "=========================================================================="
    echo "✅ Data processing completed successfully"
    echo "✅ Data has been split into train/test sets"
    echo "✅ dataset.json has been created for training"
    echo "✅ Virtual environment has been cleaned up"
    echo
    echo "Configuration used:"
    echo "  📁 Data Directory: $DATA_DIR"
    echo "  📊 Split Ratio: $SPLIT_RATIO"
    echo "  🎲 Random Seed: $RANDOM_SEED"
    echo
    echo "Output structure:"
    echo "  ├── imagesTr/          (training images)"
    echo "  ├── labelsTr/          (training labels)"
    echo "  ├── imagesTs/          (test images)"  
    echo "  ├── labelsTs/          (test labels)"
    echo "  └── dataset.json       (dataset configuration)"
    echo
    echo "Log files have been created with detailed processing information."
    echo "=========================================================================="
}

# Cleanup function for error handling
cleanup_on_error() {
    if [ $? -ne 0 ]; then
        error "Setup failed. Check the error messages above."
        echo
        echo "Common issues:"
        echo "  - Missing or incorrect data directory structure"
        echo "  - Invalid split ratio (must be between 0.0 and 1.0)"
        echo "  - Invalid random seed (must be a positive integer)"
        echo "  - Python version too old (need 3.6+)"
        echo "  - Network issues during package installation"
        echo "  - Insufficient disk space"
        
        # Attempt cleanup
        cleanup_venv
    fi
}

# Set trap for cleanup
trap cleanup_on_error EXIT

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate parameters
    validate_parameters
    
    print_header
    
    # Environment checks
    check_python
    check_venv
    check_directories
    check_scripts
    
    # Virtual environment setup
    create_venv
    activate_venv
    upgrade_pip
    install_packages
    
    # Data processing
    run_data_split
    run_dataset_creation
    
    # Verification and cleanup
    verify_output
    cleanup_venv
    print_summary
    
    success "All operations completed successfully!"
}

# Run main function with all arguments
main "$@"