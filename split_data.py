import os
import shutil
import random
import logging
import argparse
from tqdm import tqdm
from datetime import datetime
from pathlib import Path

def setup_logging():
    """Set up minimal logging configuration"""
    log_filename = f"data_split_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    
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
    parser = argparse.ArgumentParser(description='Split GRACE data into train/test sets')
    
    parser.add_argument('--base-dir', type=str, required=True,
                       help='Base directory containing images/ and labels/ folders')
    parser.add_argument('--split-ratio', type=float, required=True,
                       help='Train ratio (0.0-1.0), e.g., 0.9 means 90% train, 10% test')
    parser.add_argument('--random-seed', type=int, required=True,
                       help='Random seed for reproducibility')
    
    return parser.parse_args()

def validate_arguments(args, logger):
    """Validate command line arguments"""
    # Validate base directory
    if not os.path.exists(args.base_dir):
        logger.error(f"Base directory does not exist: {args.base_dir}")
        raise FileNotFoundError(f"Base directory not found: {args.base_dir}")
    
    # Validate split ratio
    if not (0.0 < args.split_ratio < 1.0):
        logger.error(f"Split ratio must be between 0.0 and 1.0, got: {args.split_ratio}")
        raise ValueError(f"Invalid split ratio: {args.split_ratio}")
    
    # Validate directories exist
    image_dir = os.path.join(args.base_dir, "images")
    label_dir = os.path.join(args.base_dir, "labels")
    
    if not os.path.exists(image_dir):
        logger.error(f"Images directory not found: {image_dir}")
        raise FileNotFoundError(f"Images directory not found: {image_dir}")
    
    if not os.path.exists(label_dir):
        logger.error(f"Labels directory not found: {label_dir}")
        raise FileNotFoundError(f"Labels directory not found: {label_dir}")
    
    logger.info(f"Using base directory: {args.base_dir}")
    logger.info(f"Split ratio: {args.split_ratio} ({args.split_ratio*100:.1f}% train)")
    logger.info(f"Random seed: {args.random_seed}")

def create_directories(dest_folders, logger):
    """Create destination directories"""
    for folder_name, path in dest_folders.items():
        os.makedirs(path, exist_ok=True)
    logger.info("Created output directories")

def split_and_copy(group_files, group_name, image_dir, label_dir, dest_folders, logger, train_ratio):
    """Split files into train/test and copy them with progress tracking"""
    
    if not group_files:
        logger.warning(f"No files found for {group_name}")
        return
    
    n_total = len(group_files)
    n_train = int(n_total * train_ratio)
    
    # Shuffle files for random split
    random.shuffle(group_files)
    train_files = group_files[:n_train]
    test_files = group_files[n_train:]
    
    logger.info(f"{group_name}: {len(train_files)} train, {len(test_files)} test files")
    
    # Copy training files
    if train_files:
        with tqdm(train_files, desc="Training files", unit="file", leave=False) as pbar:
            for fname in pbar:
                try:
                    # Copy image and label files
                    shutil.copy2(os.path.join(image_dir, fname), 
                               os.path.join(dest_folders["imagesTr"], fname))
                    shutil.copy2(os.path.join(label_dir, fname), 
                               os.path.join(dest_folders["labelsTr"], fname))
                except Exception as e:
                    logger.error(f"Error copying {fname}: {e}")
                    raise
    
    # Copy testing files
    if test_files:
        with tqdm(test_files, desc="Testing files", unit="file", leave=False) as pbar:
            for fname in pbar:
                try:
                    # Copy image and label files
                    shutil.copy2(os.path.join(image_dir, fname), 
                               os.path.join(dest_folders["imagesTs"], fname))
                    shutil.copy2(os.path.join(label_dir, fname), 
                               os.path.join(dest_folders["labelsTs"], fname))
                except Exception as e:
                    logger.error(f"Error copying {fname}: {e}")
                    raise

def main():
    # Parse arguments
    args = parse_arguments()
    
    # Set up logging
    logger = setup_logging()
    logger.info("Starting GRACE Data Split Process")
    
    try:
        # Validate arguments
        validate_arguments(args, logger)
        
        # Set seed for reproducibility
        random.seed(args.random_seed)
        
        # Define paths
        base_dir = args.base_dir
        image_dir = os.path.join(base_dir, "images")
        label_dir = os.path.join(base_dir, "labels")
        
        # Output folders
        dest_folders = {
            "imagesTr": os.path.join(base_dir, "imagesTr"),
            "imagesTs": os.path.join(base_dir, "imagesTs"),
            "labelsTr": os.path.join(base_dir, "labelsTr"),
            "labelsTs": os.path.join(base_dir, "labelsTs"),
        }
        
        # Create destination directories
        create_directories(dest_folders, logger)
        
        # Find all .nii files
        all_image_files = [f for f in os.listdir(image_dir) if f.endswith('.nii')]
        logger.info(f"Found {len(all_image_files)} .nii files")
        
        if not all_image_files:
            logger.error("No .nii files found in the image directory!")
            raise FileNotFoundError("No .nii files found")
        
        # Process all data
        split_and_copy(all_image_files, "All Data", image_dir, label_dir, 
                      dest_folders, logger, args.split_ratio)
        
        # Summary
        logger.info("Data split completed successfully!")
        for folder_name, folder_path in dest_folders.items():
            count = len([f for f in os.listdir(folder_path) if f.endswith('.nii')])
            logger.info(f"{folder_name}: {count} files")
            
    except Exception as e:
        logger.error(f"Data split failed: {e}")
        raise

if __name__ == "__main__":
    main()