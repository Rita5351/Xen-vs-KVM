import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
 
# Impostazioni grafiche riprese dal tuo script originale
sns.set_theme(style="whitegrid")
plt.rcParams.update({
    'font.size': 11,
    'axes.labelsize': 12,
    'axes.titlesize': 14,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'figure.titlesize': 16,
    'legend.fontsize': 10
})
 
# Dizionario per mappare i file alle relative etichette
# (assicurati di aver inserito tutti i kernel e le VM testate)
test_files = {
    Path('Xen/tests_various_stessors/NRT-pinned__guest-rt5-pinned-hvm__stressor-baseline.log'): 'BASELINE',
    Path('Xen/tests_various_stessors/NRT-pinned__guest-rt5-pinned-hvm__stressor-cache.log'): 'CACHE',
    Path('Xen/tests_various_stessors/NRT-pinned__guest-rt5-pinned-hvm__stressor-interrupts.log'): 'INTERRUPTS',
    Path('Xen/tests_various_stessors/NRT-pinned__guest-rt5-pinned-hvm__stressor-rawsock.log'): 'RAWSOCK'
}
 
def load_histogram_data(filepath, config_name):
    """Carica i dati del test TACLe ed espande le frequenze per il boxplot"""
    try:
        data = np.loadtxt(filepath, comments='#')
        latencies = data[:, 0]
        frequencies = data[:, 1].astype(int)
 
        # Ricostruisce l'array originale dei campioni
        expanded_latencies = np.repeat(latencies, frequencies)
 
        return pd.DataFrame({
            'Latency_us': expanded_latencies,
            'Configuration': config_name
        })
    except FileNotFoundError:
        print(f"[ERRORE] File non trovato: {filepath}")
        return pd.DataFrame()
 
def main():
    df_list = []
 
    print("=== CARICAMENTO DATI TACLE ===")
    for filepath, label in test_files.items():
        print(f"Elaborazione: {label}...")
        df_config = load_histogram_data(filepath, label)
        if not df_config.empty:
            df_list.append(df_config)
 
    if not df_list:
        print("[ERRORE] Nessun dato caricato. Controlla i percorsi dei file.")
        return
 
    # Unisce tutti i dati in un singolo DataFrame Pandas
    df_all = pd.concat(df_list, ignore_index=True)
 
    # --- Stampa dei Valori di Picco Massimo ---
    print("\n=== VALORI DI LATENZA MASSIMA (PICCO) ===")
    max_latencies = df_all.groupby('Configuration')['Latency_us'].max()
    for config, max_lat in max_latencies.items():
        print(f"{config}: {max_lat} µs")
 
    # --- Creazione Boxplot ---
    plt.figure(figsize=(12, 7))
 
    ax = sns.boxplot(
    data=df_all,
    x='Configuration',
    y='Latency_us',
    palette="Set2",
    width=0.6,
    # Sostituisci fliersize con flierprops e attiva il rasterized
    flierprops={"marker": ".", "markersize": 2, "alpha": 0.5, "rasterized": True}
)
 
    # La scala logaritmica è fortemente consigliata per visualizzare
    # la distribuzione mantenendo visibili i picchi anomali
    ax.set_yscale('log')
 
    plt.title('stressor NRT pinned guest rt5 pinned HVM', pad=20, fontweight='bold')
    plt.xlabel('System Configuration', labelpad=12)
    plt.ylabel(r'Latency ($\mu s$) [Log Scale]', labelpad=12)
 
    plt.grid(True, which="both", linestyle=":", alpha=0.6)
    plt.tight_layout()
 
    # Salvataggio
    output_filename = 'stressor_NRT_pinned_guest_rt5_pinned_HVM_boxplot.svg'
    plt.savefig(output_filename, format='svg', bbox_inches='tight')
    plt.close()
    print(f"\n[OK] Boxplot salvato con successo: {output_filename}")
 
if __name__ == "__main__":
    main()