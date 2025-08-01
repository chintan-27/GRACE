# 🧠 GRACE: General, Rapid, And Comprehensive whole-hEad Segmentation

**Precise and Rapid Whole-Head Segmentation from Magnetic Resonance Images of Older Adults using Deep Learning**  
Deep learning pipeline for fast and accurate 11-tissue segmentation of T1-weighted MRIs in older adults.

---

## 1. Description

**GRACE** is a high-performance, open-source segmentation pipeline built on MONAI’s UNETR. It segments 11 tissue classes (white matter, gray matter, eyes, CSF, air, blood vessel, cancellous bone, cortical bone, skin, fat, muscle) from raw T1-weighted MRI without external preprocessing. Trained on 177 meticulously corrected, manually reviewed segmentations of older adult heads, GRACE delivers state-of-the-art accuracy (avg. Hausdorff Distance = 0.21) and speed.

---

## 2. Paper

This repository implements the methods and data behind:

**Precise and Rapid Whole-Head Segmentation from Magnetic Resonance Images of Older Adults using Deep Learning**  
Skylar E. Stolte<sup>1</sup>, Aprinda Indahlastari<sup>2,3</sup>, Jason Chen<sup>4</sup>, Alejandro Albizu<sup>2,5</sup>, Ayden Dunn<sup>3</sup>, Samantha Pederson<sup>3</sup>, Kyle B. See<sup>1</sup>, Adam J. Woods<sup>2,3,5</sup>, and **Ruogu Fang**<sup>1,2,6,*</sup>  

<sup>1</sup>J. Crayton Pruitt Family Dept. of Biomedical Engineering, UF  
<sup>2</sup>Center for Cognitive Aging & Memory, McKnight Brain Institute, UF  
<sup>3</sup>Dept. of Clinical & Health Psychology, UF  
<sup>4</sup>Dept. of Computer & Information Science & Engineering, UF  
<sup>5</sup>Dept. of Neuroscience, College of Medicine, UF  
<sup>6</sup>Dept. of Electrical & Computer Engineering, UF  

*Imaging NeuroScience*  
📄 [Paper](https://direct.mit.edu/imag/article/doi/10.1162/imag_a_00090/119208/Precise-and-rapid-whole-head-segmentation-from) | 💻 [Code](https://github.com/lab-smile/GRACE)

---

## 3. Table of Contents

1. [Installation](#installation)  
2. [Usage](#usage)  
   - [MATLAB Segmentation Label Preparation](#matlab-segmentation-label-preparation)  
   - [Build Container](#build-container)  
   - [Training](#training)  
   - [Testing](#testing)  
   - [File Conversion](#file-conversion)  
   - [Visualization](#visualization)  
3. [Examples / Demos](#examples--demos)  
4. [Configuration](#configuration)  
5. [Project Structure](#project-structure)  
6. [Contributing](#contributing)  
7. [License](#license)  
8. [Authors / Acknowledgments](#authors--acknowledgments)  
9. [Citation](#citation)  
10. [Contact](#contact)  

---

## 4. Installation

```bash
git clone https://github.com/lab-smile/GRACE.git
cd GRACE
````

---

## 5. Usage

### MATLAB Segmentation Label Preparation

1. Change directory paths inside each MATLAB script to point at your data.
2. Add the GRACE working folder to your MATLAB path.
3. Run `combine_mask.m`.

   * **MATLAB 2020b** users must modify line 56 in `combine_mask.m`:

     ```matlab
     image(index) = tissue_cond_updated.Labels(k);
     ```
4. After completion, your **`Data/`** folder will have this structure:

   ```
   Data/
   ├── ImagesTr/
   │   ├── sub-TrX_T1.nii
   │   └── …
   ├── ImagesTs/
   │   ├── sub-TsX_T1.nii
   │   └── …
   ├── LabelsTr/
   │   ├── sub-TrX_seg.nii
   │   └── …
   └── LabelsTs/
       ├── sub-TsX_seg.nii
       └── …
   ```
5. In MATLAB, run:

   ```matlab
   make_datalist_json.m
   ```
6. Exit MATLAB and proceed below.

---

### Build Container

GRACE runs inside a Singularity container with MONAI and dependencies pre-installed:

```bash
./build_container_v08.sh
```

> **Edit** `build_container_v08.sh` first:
>
> * `--sandbox` → desired output directory
> * `--nv`      → path to your own directory

Output: a folder named `monaicore08/`.

---

### Training

Once Data and container are ready:

```bash
./train.sh
```

**Before running**, edit `train.sh` to update:

* `singularity exec --nv /path/to/monaicore08`
* `--bind /path/to/monaicore08`
* `data_dir=/path/to/your/Data`
* `model_save_name=YOUR_MODEL_NAME`
* Optional: `--max_iter` (e.g., 100 for \~1 hr, 25 000 for \~24 hr)

---

### Testing

```bash
./test.sh
```

**Edit** `test.sh` as you did for training:

* Paths
* `model_save_name` (must match training)
* Output: a `.mat` file per test subject

---

### File Conversion

Convert the MATLAB `.mat` outputs to NIfTI:

```bash
cd mat_to_nii/
# Edit main.py → set FILES = [ 'sub-X.mat', … ]
python main.py
```

You can also interconvert `.nii` ↔︎ `.raw` under `Nii_Raw_Interconversion/`.

---

### Visualization

Inside `Visualization Code/`, open `main_v2.py`:

1. Edit `SUBLIST` with your image IDs.
2. Set file paths for T1 and GRACE output.
3. Run:

   ```bash
   python main_v2.py
   ```

---

## 6. Examples / Demos

<div align="center">
  <img src="https://github.com/lab-smile/GRACE/blob/main/Images/Figure3.png" width="700"><br>
  <b>Label mapping for GRACE’s 11 tissues.</b>
</div>

<div align="center">
  <img src="https://github.com/lab-smile/GRACE/blob/main/Images/Figure11.png" width="700"><br>
  <b>Comparison with existing segmentation pipelines.</b>
</div>

---

## 7. Configuration

Any additional `.env`, JSON, or YAML can be edited in the `configs/` folder (if added).
Defaults are loaded from `defaults.json`.

---

## 8. Project Structure

```
GRACE/
├── Images/                   # Figures & illustrations
├── MATLAB_versions/          # combine_mask.m, make_datalist_json.m
├── Nii_Raw_Interconversion/  # .nii ↔︎ .raw scripts
├── ToolboxComparison/        # SPM toolbox converters
├── Visualization Code/       # main_v2.py visualizations
├── mat_to_nii/               # .mat → .nii converter
├── build_container_v08.sh    # Singularity build script
├── calculate_metrics.py      # Hausdorff, Dice, etc.
├── train.sh / train.py       # Training wrapper & code
├── test.sh  / test.py        # Testing wrapper & code
├── makeGRACEjson.py          # Python datalist JSON creator
├── README.md                 # This file
└── LICENSE                   # MIT License
```

---

## 9. Contributing

1. Fork the repo
2. Create branch: `feature/awesome-feature`
3. Commit changes & push
4. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## 10. License

This project is licensed under the **MIT License**.
See [LICENSE](LICENSE) for full text.

---

## 11. Authors / Acknowledgments

**Authors:**
Skylar E. Stolte, Aprinda Indahlastari, Jason Chen, Alejandro Albizu, Ayden Dunn, Samantha Pederson, Kyle B. See, Adam J. Woods, **Ruogu Fang**

**Supported by:**

* NIH/NIA: RF1AG071469, R01AG054077
* NSF: 1842473, 1908299, 2123809
* NSF-AFRL INTERN Supplement: 2130885
* UF McKnight Brain Institute & Memory Center
* McKnight Brain Research Foundation
* NVIDIA AI Technology Center (NVAITC)

**Base model:**
UNETR from MONAI research contributions
[https://github.com/Project-MONAI/research-contributions/tree/main/UNETR](https://github.com/Project-MONAI/research-contributions/tree/main/UNETR)

---

## 12. Citation

```bibtex
@InProceedings{stolte2024,
  author="Stolte, Skylar E. and Indahlastari, Aprinda and Chen, Jason and Albizu, Alejandro and Dunn, Ayden and Pederson, Samantha and See, Kyle B. and Woods, Adam J. and Fang, Ruogu",
  title="Precise and Rapid Whole-Head Segmentation from Magnetic Resonance Images of Older Adults using Deep Learning",
  booktitle="Imaging NeuroScience",
  year="2024",
  url="TBD"
}
```

---

## 13. Contact

📧 [Skylar Stolte](mailto:skylastolte4444@ufl.edu)
📧 [Dr. Ruogu Fang](mailto:ruogu.fang@bme.ufl.edu)

*Smart Medical Informatics Learning & Evaluation Laboratory, Dept. of Biomedical Engineering, University of Florida*

---
