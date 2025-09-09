import os
import json
import logging
import argparse
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from sklearn.model_selection import train_test_split

def setup_logging():
    """Set up minimal logging configuration"""
    log_filename = f"dataset_creation_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_filename),
            logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='Create dataset.json for GRACE training')
    
    parser.add_argument('--base-dir', type=str, required=True,
                       help='Base directory containing split data folders')
    
    return parser.parse_args()

def validate_arguments(args, logger):
    """Validate command line arguments and directory structure"""
    base_dir = Path(args.base_dir)
    
    if not base_dir.exists():
        logger.error(f"Base directory does not exist: {base_dir}")
        raise FileNotFoundError(f"Base directory not found: {base_dir}")
    
    # Define required directories
    required_dirs = {
        "imagesTr": base_dir / "imagesTr",
        "labelsTr": base_dir / "labelsTr", 
        "imagesTs": base_dir / "imagesTs"
    }
    
    missing_dirs = []
    for dir_name, dir_path in required_dirs.items():
        if not dir_path.exists():
            missing_dirs.append(f"{dir_name}: {dir_path}")
    
    if missing_dirs:
        logger.error(f"Missing required directories: {', '.join(missing_dirs)}")
        raise FileNotFoundError(f"Missing directories: {missing_dirs}")
    
    logger.info(f"Using base directory: {base_dir}")
    return required_dirs

def count_files(directory, pattern=".nii"):
    """Count files with specific pattern in directory"""
    return len(list(directory.glob(f"*{pattern}")))

def validate_file_correspondence(train_images, train_labels, logger):
    """Validate that training images and labels correspond correctly"""
    if len(train_images) != len(train_labels):
        error_msg = f"Mismatch: {len(train_images)} images vs {len(train_labels)} labels"
        logger.error(error_msg)
        raise AssertionError(error_msg)
    
    logger.info(f"Validated {len(train_images)} image-label pairs")

def build_dataset_entries(images, labels, desc):
    """Build dataset entries with progress tracking"""
    entries = []
    with tqdm(zip(images, labels), total=len(images), desc=f"Building {desc}", unit="pair", leave=False) as pbar:
        for img, lbl in pbar:
            entry = {"image": str(img), "label": str(lbl)}
            entries.append(entry)
    
    return entries

def validate_dataset_structure(dataset_dict, logger):
    """Validate the final dataset structure"""
    required_keys = ["description", "license", "modality", "labels", "name", "numTest", 
                    "numTraining", "reference", "release", "tensorImageSize", "test", 
                    "training", "validation"]
    
    missing_keys = [key for key in required_keys if key not in dataset_dict]
    if missing_keys:
        logger.error(f"Missing required keys: {missing_keys}")
        raise KeyError(f"Dataset missing required keys: {missing_keys}")
    
    # Log summary
    actual_training = len(dataset_dict["training"])
    actual_validation = len(dataset_dict["validation"])
    actual_test = len(dataset_dict["test"])
    
    logger.info(f"Dataset summary: {actual_training} train, {actual_validation} val, {actual_test} test")

def save_dataset_json(dataset_dict, output_path, logger):
    """Save dataset to JSON file with error handling"""
    try:
        # Create backup if file exists
        if output_path.exists():
            backup_path = output_path.with_suffix(f'.backup_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json')
            output_path.rename(backup_path)
            logger.info(f"Created backup: {backup_path}")
        
        with open(output_path, "w") as f:
            json.dump(dataset_dict, f, indent=4, sort_keys=True)
        
        # Verify file was written correctly
        file_size = output_path.stat().st_size
        logger.info(f"Dataset saved successfully ({file_size} bytes)")
        
        # Verify JSON is valid
        with open(output_path, "r") as f:
            json.load(f)
        logger.info("JSON validation successful")
        
    except Exception as e:
        logger.error(f"Error saving dataset: {e}")
        raise

def main():
    # Parse arguments
    args = parse_arguments()
    
    # Set up logging
    logger = setup_logging()
    logger.info("Starting Dataset JSON Creation Process")
    
    try:
        # Validate arguments and get directory paths
        directories = validate_arguments(args, logger)
        
        # Define metadata
        dataset_metadata = {
            "description": "AISEG V5 - Code Validation",
            "license": "UF",
            "modality": {"x0": "T1"},
            "labels": {
                "x0": "background",
                "x1": "wm",
                "x2": "gm", 
                "x3": "eyes",
                "x4": "csf",
                "x5": "air",
                "x6": "blood",
                "x7": "cancellous",
                "x8": "cortical",
                "x9": "skin",
                "x10": "fat",
                "x11": "muscle"
            },
            "name": "ACT",
            "reference": "NA",
            "release": "NA",
            "tensorImageSize": "3D"
        }
        
        logger.info(f"Dataset: {dataset_metadata['name']} ({len(dataset_metadata['labels'])} classes)")
        
        # Process test data
        test_files = sorted(directories["imagesTs"].glob("*.nii"))
        test = [str(f) for f in test_files]
        numTest = len(test_files)
        logger.info(f"Test files: {numTest}")
        
        # Process training data
        train_images = sorted(directories["imagesTr"].glob("*.nii"))
        train_labels = sorted(directories["labelsTr"].glob("*.nii"))
        
        # Validate correspondence
        validate_file_correspondence(train_images, train_labels, logger)
        
        # Create 90/10 train/validation split
        train_imgs, val_imgs, train_lbls, val_lbls = train_test_split(
            train_images, train_labels, 
            test_size=0.10, 
            random_state=42,
            shuffle=True
        )
        
        logger.info(f"Split: {len(train_imgs)} train, {len(val_imgs)} validation")
        
        # Build dataset entries
        training = build_dataset_entries(train_imgs, train_lbls, "training")
        validation = build_dataset_entries(val_imgs, val_lbls, "validation")
        
        numTraining = len(train_images)
        
        # Build final dataset structure
        dataset_dict = {
            **dataset_metadata,
            "numTest": numTest,
            "numTraining": numTraining,
            "test": test,
            "training": training,
            "validation": validation
        }
        
        # Validate final structure
        validate_dataset_structure(dataset_dict, logger)
        
        # Save to JSON
        output_path = Path("dataset.json")
        save_dataset_json(dataset_dict, output_path, logger)
        
        logger.info("Dataset JSON creation completed successfully!")
        
    except Exception as e:
        logger.error(f"Dataset creation failed: {e}")
        raise

if __name__ == "__main__":
    main()