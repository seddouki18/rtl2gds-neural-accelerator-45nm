# ==============================================================================
# PROJET : ACCÉLÉRATEUR MATÉRIEL ADAS (VERSION FINALE ÉQUILIBRÉE)
# Architecture : 4 -> 8 -> 16 -> 16 -> 2 | Bit-Exact SystemVerilog / ModelSim
# ==============================================================================

import os
import random
import time
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import WeightedRandomSampler
from sklearn.model_selection import train_test_split

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

print("=" * 80)
print(f"✅ ÉTAPE 1 : Initialisation terminée. Device : {DEVICE}")
print("=" * 80)

# ==============================================================================
# ÉTAPE 2 : Génération Équilibrée avec Renforcement de l'Axe Frontal (|Angle| < 8°)
# ==============================================================================
t0 = time.time()
print("\n🔄 ÉTAPE 2 : Génération du Dataset ADAS équilibré (160 000 échantillons)...")

rng = np.random.default_rng(SEED)
SPEED_MAX_MPS = 120.0 / 3.6
# 1. Base Globale Uniforme (80 000 échantillons)
N_BASE = 80000
d_base = rng.uniform(2.0, 100.0, N_BASE)
s_base = rng.uniform(10.0, 120.0, N_BASE)
a_base = rng.uniform(-30.0, 30.0, N_BASE)
r_base = rng.uniform(-SPEED_MAX_MPS, SPEED_MAX_MPS, N_BASE)
# 2. Lot Ciblé Frontal Pur : TTC < 1.2s & |Angle| < 7.5° (30 000 échantillons -> AEB Seul Garanti)
N_FRONT = 30000
s_front = rng.uniform(40.0, 120.0, N_FRONT)
r_front = rng.uniform(-SPEED_MAX_MPS, 0.0, N_FRONT)
v_front = (s_front / 3.6) - r_front
ttc_front = rng.uniform(0.1, 1.15, N_FRONT)
d_front = np.clip(ttc_front * v_front, 2.0, 45.0)
a_front = rng.uniform(-7.5, 7.5, N_FRONT)
# 3. Lot Ciblé Latéral Danger : TTC < 1.4s & |Angle| >= 8.5° (30 000 échantillons -> AEB + Évitement)
N_SIDE_DANGER = 30000
s_sd = rng.uniform(40.0, 120.0, N_SIDE_DANGER)
r_sd = rng.uniform(-SPEED_MAX_MPS, 0.0, N_SIDE_DANGER)
v_sd = (s_sd / 3.6) - r_sd
ttc_sd = rng.uniform(0.1, 1.35, N_SIDE_DANGER)
d_sd = np.clip(ttc_sd * v_sd, 2.0, 45.0)
a_sd = rng.choice([-1.0, 1.0], size=N_SIDE_DANGER) * rng.uniform(8.5, 30.0, N_SIDE_DANGER)

# 4. Lot Ciblé Évitement Seul : 1.5s <= TTC < 2.7s & |Angle| >= 8.5° (20 000 échantillons)
N_SIDE_EVIT = 20_000
s_se = rng.uniform(30.0, 110.0, N_SIDE_EVIT)
r_se = rng.uniform(-15.0, 10.0, N_SIDE_EVIT)
v_se = np.maximum((s_se / 3.6) - r_se, 5.0)
ttc_se = rng.uniform(1.55, 2.70, N_SIDE_EVIT)
d_se = np.clip(ttc_se * v_se, 15.0, 70.0)
a_se = rng.choice([-1.0, 1.0], size=N_SIDE_EVIT) * rng.uniform(8.5, 30.0, N_SIDE_EVIT)

# Concaténation de l'ensemble
distances = np.concatenate([d_base, d_front, d_sd, d_se])
speeds = np.concatenate([s_base, s_front, s_sd, s_se])
angles = np.concatenate([a_base, a_front, a_sd, a_se])
relative_speeds = np.concatenate([r_base, r_front, r_sd, r_se])
NUM_SAMPLES = len(distances)

# Calcul physique vectorisé
v_mps = speeds / 3.6
v_app = v_mps - relative_speeds
ttc = np.divide(distances, v_app, out=np.full(NUM_SAMPLES, 999.0, dtype=np.float64), where=(v_app > 0.5))
abs_angles = np.abs(angles)

cond1 = (ttc < 1.2) & (abs_angles < 8.0)                         # 0: AEB seul
cond2 = (ttc < 1.5) & (abs_angles >= 8.0)                        # 1: AEB + Évitement
cond3 = (ttc >= 1.5) & (ttc < 2.8) & (abs_angles >= 8.0)         # 2: Évitement seul
# Reste -> 3: Conduite Normale

score_aeb = np.select([cond1, cond2, cond3], [1.0, 1.0, -1.0], default=-1.0).astype(np.float32)
score_evit = np.select([cond1, cond2, cond3], [-1.0, 1.0, 1.0], default=-1.0).astype(np.float32)
class_label = np.select([cond1, cond2, cond3], [0, 1, 2], default=3).astype(np.int64)

dataset = pd.DataFrame({
    "Distance": distances, "Speed": speeds, "Angle": angles, "Relative_Speed": relative_speeds,
    "Score_AEB": score_aeb, "Score_Evitement": score_evit, "Class": class_label
})
dataset.to_csv("dataset_adas.csv", index=False)

class_names = ["AEB seul", "AEB+Évitement", "Évitement seul", "Normal"]
print(f"✅ Dataset généré : {len(dataset)} lignes en {time.time()-t0:.3f}s")
for c in range(4):
    n = (class_label == c).sum()
    print(f"    {class_names[c]:<16}: {n:>6} ({100*n/NUM_SAMPLES:5.1f}%)")

# ==============================================================================
# ÉTAPE 3 : Normalisation et Partitionnement Stratifié
# ==============================================================================
print("\n🔄 ÉTAPE 3 : Partitionnement Stratifié (75% Train / 20% Test / 5% Vérif)...")

train_df, temp_df = train_test_split(dataset, test_size=0.25, random_state=SEED, shuffle=True, stratify=dataset["Class"])
test_df, verif_df = train_test_split(temp_df, test_size=0.20, random_state=SEED, shuffle=True, stratify=temp_df["Class"])

X_MIN = np.array([2.0, 10.0, -30.0, -SPEED_MAX_MPS], dtype=np.float32)
X_MAX = np.array([100.0, 120.0, 30.0, SPEED_MAX_MPS], dtype=np.float32)

def normalize(val_raw):
    return 2.0 * (val_raw - X_MIN) / (X_MAX - X_MIN) - 1.0

INPUT_COLS = ["Distance", "Speed", "Angle", "Relative_Speed"]
OUTPUT_COLS = ["Score_AEB", "Score_Evitement"]

X_train_t = torch.tensor(normalize(train_df[INPUT_COLS].to_numpy(dtype=np.float32)), dtype=torch.float32, device=DEVICE)
Y_train_t = torch.tensor(train_df[OUTPUT_COLS].to_numpy(dtype=np.float32), dtype=torch.float32, device=DEVICE)
class_train = train_df["Class"].to_numpy()

X_test_t = torch.tensor(normalize(test_df[INPUT_COLS].to_numpy(dtype=np.float32)), dtype=torch.float32, device=DEVICE)
Y_test_t = torch.tensor(test_df[OUTPUT_COLS].to_numpy(dtype=np.float32), dtype=torch.float32, device=DEVICE)

X_verif_t = torch.tensor(normalize(verif_df[INPUT_COLS].to_numpy(dtype=np.float32)), dtype=torch.float32, device=DEVICE)
Y_verif_t = torch.tensor(verif_df[OUTPUT_COLS].to_numpy(dtype=np.float32), dtype=torch.float32, device=DEVICE)

class_counts = np.bincount(class_train, minlength=4)
class_weights = 1.0 / np.maximum(class_counts, 1)
sample_weights = class_weights[class_train]
sampler = WeightedRandomSampler(weights=torch.tensor(sample_weights, dtype=torch.double), num_samples=len(sample_weights), replacement=True)

# ==============================================================================
# ÉTAPE 4 : Architecture Réseau (ReLU Standard — Bit-Exact Hardware)
# ==============================================================================
print("\n🔄 ÉTAPE 4 : Initialisation du modèle Hardware...")

class ADAS_Model(nn.Module):
    def __init__(self):
        super().__init__()
        self.couche_1 = nn.Linear(4, 8)
        self.couche_2 = nn.Linear(8, 16)
        self.couche_3 = nn.Linear(16, 16)
        self.couche_4 = nn.Linear(16, 2)
        self.act = nn.ReLU()

        for m in [self.couche_1, self.couche_2, self.couche_3]:
            nn.init.kaiming_uniform_(m.weight, a=0, nonlinearity='relu')
            nn.init.constant_(m.bias, 0.05)
        nn.init.xavier_uniform_(self.couche_4.weight)
        nn.init.constant_(self.couche_4.bias, 0.0)

    def forward(self, x):
        x = self.act(self.couche_1(x))
        x = self.act(self.couche_2(x))
        x = self.act(self.couche_3(x))
        x = self.couche_4(x)
        return x

modele = ADAS_Model().to(DEVICE)
total_params = sum(p.numel() for p in modele.parameters())
print(f"✅ Modèle initialisé ! Total paramètres : {total_params} (490 octets).")

# ==============================================================================
# ÉTAPE 5 : Entraînement Optimisé
# ==============================================================================
print("\n🔄 ÉTAPE 5 : Lancement de l'entraînement...")

criterion = nn.MSELoss()
optimizer = optim.Adam(modele.parameters(), lr=0.003)
scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='max', factor=0.5, patience=8)

EPOCHS = 100
BATCH_SIZE = 128
best_test_acc = -1.0

def classify_vectorized(s_aeb, s_evit):
    aeb_active = s_aeb > 0
    evit_active = s_evit > 0
    cls = np.full(len(s_aeb), 3, dtype=np.int8)
    cls[aeb_active & ~evit_active] = 0
    cls[aeb_active & evit_active] = 1
    cls[~aeb_active & evit_active] = 2
    return cls

target_class_test = classify_vectorized(Y_test_t[:, 0].cpu().numpy(), Y_test_t[:, 1].cpu().numpy())
train_indices = torch.arange(X_train_t.size(0))
loader_batches = torch.utils.data.DataLoader(train_indices, batch_size=BATCH_SIZE, sampler=sampler)

t0 = time.time()
for epoch in range(EPOCHS):
    modele.train()
    train_loss_accum = 0.0
    n_seen = 0
    for idx in loader_batches:
        idx = idx.to(DEVICE)
        preds = modele(X_train_t[idx])
        loss = criterion(preds, Y_train_t[idx])
        optimizer.zero_grad(set_to_none=True)
        loss.backward()
        optimizer.step()
        train_loss_accum += loss.item() * len(idx)
        n_seen += len(idx)
    train_loss = train_loss_accum / n_seen

    modele.eval()
    with torch.no_grad():
        test_preds = modele(X_test_t)
        test_loss = criterion(test_preds, Y_test_t).item()
        pred_class_test = classify_vectorized(test_preds[:, 0].cpu().numpy(), test_preds[:, 1].cpu().numpy())
        test_acc = (pred_class_test == target_class_test).mean() * 100.0

    scheduler.step(test_acc)

    if test_acc > best_test_acc:
        best_test_acc = test_acc
        torch.save(modele.state_dict(), "best_model.pth")

    if (epoch + 1) % 20 == 0 or epoch == 0:
        lr = optimizer.param_groups[0]['lr']
        print(f"Époque [{epoch+1:03d}/{EPOCHS}] | Train Loss: {train_loss:.5f} | Test Loss: {test_loss:.5f} | Test Acc: {test_acc:.2f}% | LR: {lr:.5f}")

print(f"\n✅ Entraînement terminé en {time.time()-t0:.2f}s ! Meilleure Accuracy : {best_test_acc:.2f}%")
modele.load_state_dict(torch.load("best_model.pth", map_location=DEVICE))
modele.eval()

# ==============================================================================
# ÉTAPE 6 : Test de Balayage d'Angle (Frontière 8°) & Test des 5 Scénarios
# ==============================================================================
print("\n" + "=" * 80)
print("📊 ÉTAPE 6A : Balayage d'Angle (Vérification de la Frontière à 8°)")
print("=" * 80)

for a_deg in [0, 1, 2, 4, 6, 8, 10, 12, 15]:
    raw = np.array([10.0, 100.0, float(a_deg), -3.0], dtype=np.float32)
    norm = normalize(raw)
    x = torch.tensor(norm, dtype=torch.float32).unsqueeze(0).to(DEVICE)
    with torch.no_grad():
        pred = modele(x).cpu().numpy()[0]
    score_aeb_q = int(np.round(pred[0] * 32.0))
    score_evit_q = int(np.round(pred[1] * 32.0))
    decision = "AEB + EVIT" if score_evit_q > 0 else "AEB seul"
    expected = "AEB + EVIT" if a_deg >= 8 else "AEB seul"
    ok = "✅" if decision == expected else "❌"
    print(f"    Angle = {a_deg:2d}° -> Score AEB = {score_aeb_q:+4d} | Score Évit = {score_evit_q:+4d} -> {decision:<10} (Attendu: {expected}) {ok}")

print("\n" + "=" * 80)
print("📊 ÉTAPE 6B : Vérification Explicite de vos 5 Cas Physiques")
print("=" * 80)

test_5_samples = np.array([
    [5.0, 100.0, 0.0, -2.0],
    [10.0, 120.0, 2.0, -4.0],
    [20.0, 100.0, 0.0, -5.0],
    [15.0, 90.0, 0.0, -3.0],
    [25.0, 120.0, 2.0, -4.0]
], dtype=np.float32)

with torch.no_grad():
    p5 = modele(torch.tensor(normalize(test_5_samples), dtype=torch.float32).to(DEVICE)).cpu().numpy()

for i in range(5):
    s_aeb_i = int(np.round(p5[i, 0] * 32.0))
    s_evi_i = int(np.round(p5[i, 1] * 32.0))
    dec_i = "Freinage d'Urgence (AEB)" if (s_aeb_i > 0 and s_evi_i <= 0) else "Freinage + Évitement"
    print(f"Test #{i+1} : Score AEB = {s_aeb_i:+4d} | Score Évit = {s_evi_i:+4d} -> {dec_i}")

# ==============================================================================
# ÉTAPE 7 : Quantification INT8 Bit-Exact (Scale = 32.0)
# ==============================================================================
print("\n" + "=" * 80)
print("🔄 ÉTAPE 7 : Quantification INT8 et Export de weights.txt...")
print("=" * 80)

SCALE_FACTOR = 32.0

def quantize_tensor(tensor, scale):
    data = tensor.detach().cpu().numpy().flatten()
    return np.clip(np.round(data * scale), -128, 127).astype(np.int8)

w1 = quantize_tensor(modele.couche_1.weight, SCALE_FACTOR); b1 = quantize_tensor(modele.couche_1.bias, SCALE_FACTOR)
w2 = quantize_tensor(modele.couche_2.weight, SCALE_FACTOR); b2 = quantize_tensor(modele.couche_2.bias, SCALE_FACTOR)
w3 = quantize_tensor(modele.couche_3.weight, SCALE_FACTOR); b3 = quantize_tensor(modele.couche_3.bias, SCALE_FACTOR)
w4 = quantize_tensor(modele.couche_4.weight, SCALE_FACTOR); b4 = quantize_tensor(modele.couche_4.bias, SCALE_FACTOR)

all_weights = np.concatenate([w1, b1, w2, b2, w3, b3, w4, b4])
assert len(all_weights) == 490

with open("weights.txt", "w") as f:
    for val in all_weights:
        f.write(f"{int(val) & 0xFF:02X}\n")

print(f"✅ weights.txt exporté avec succès (490 octets ordonnés).")

# ==============================================================================
# ÉTAPE 8 : Export des 40 Scénarios pour ModelSim (sensor_data.txt)
# (1-10: AEB seul | 11-20: Évitement seul | 21-30: AEB+Évit | 31-40: Normal)
# ==============================================================================
print("\n🔄 ÉTAPE 8 : Exportation ordonnée des 40 tests (sensor_data.txt)...")

df_class1 = test_df[(test_df["Score_AEB"] == 1.0) & (test_df["Score_Evitement"] == -1.0)].head(10)
df_class2 = test_df[(test_df["Score_AEB"] == 1.0) & (test_df["Score_Evitement"] == 1.0)].head(10)
df_class3 = test_df[(test_df["Score_AEB"] == -1.0) & (test_df["Score_Evitement"] == 1.0)].head(10)
df_class4 = test_df[(test_df["Score_AEB"] == -1.0) & (test_df["Score_Evitement"] == -1.0)].head(10)

selected_40_df = pd.concat([df_class1, df_class3, df_class2, df_class4], ignore_index=True)

with open("sensor_data.txt", "w") as f:
    for _, row in selected_40_df.iterrows():
        d = int(round(row["Distance"])) & 0xFF
        s = int(round(row["Speed"])) & 0xFF
        a = int(round(row["Angle"])) & 0xFF
        r = int(round(row["Relative_Speed"])) & 0xFF
        f.write(f"{d:02X}{s:02X}{a:02X}{r:02X}\n")

print("✅ sensor_data.txt exporté avec succès (40 vecteurs 32-bit).")