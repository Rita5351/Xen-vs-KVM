from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

# 1. Carica i dati ignorando le righe di commento (che iniziano con #)
# Sostituisci il nome del file se necessario

# Test senza stress
test_classes = [Path('KVM/tests/results_nrt_nrt_stresshost_isolated.log'),
                Path('KVM/tests/results_nrt_rt_stresshost_isolated.log'),
                Path('KVM/tests/results_rt_nrt_stresshost_isolated.log'),
                Path('KVM/tests/results_rt_rt_stresshost_isolated.log')]

# Test con stress (verifica che l'estensione finale sia corretta)
# test_classes = [Path('KVM/tests/results_nrt_nrt_stresshost.log'),
#                 Path('KVM/tests/results_nrt_rt_stresshost.log'),
#                 Path('KVM/tests/results_rt_nrt_stresshost.log'),
#                 Path('KVM/tests/results_rt_rt_stresshost.log')]

def plot_data(filename):
    data = np.loadtxt(filename, comments='#')
    latencies = data[:, 0]
    frequencies = data[:, 1]
    cdf = np.cumsum(frequencies) / np.sum(frequencies)
    plt.plot(latencies, cdf)


plt.figure(figsize=(10, 6))
for filename in test_classes:
    plot_data(filename)

# Formattazione
plt.xlabel(r'Latency ($\mu s$)') # Aggiunta la 'r' per risolvere il SyntaxWarning
plt.ylabel('Cumulative Distribution Function (CDF)')
plt.title('Cyclictest latencies on KVM')
plt.grid(True, linestyle='--', alpha=0.7)

# Limiti assi
plt.xlim(left=0, right=100)
plt.ylim(0, 1.05)
plt.legend(['NRT Kernel, NRT VM',
            'NRT Kernel, RT VM',
            'RT Kernel, NRT VM',
            'RT Kernel, RT VM'])

# Opzionale: Salva su file o mostra a schermo e salva i dati per LaTeX
plt.savefig('kvm_nonoise.svg')
# plt.savefig('kvm_stress.svg')
plt.show()

# --- ESPORTAZIONE PER LATEX ---
# np.savetxt("kvm_nonoise.txt", np.column_stack((latencies, cdf)),
#            fmt="%.0f %.6f", header="latency cdf", comments="")
# print("Dati CDF esportati per LaTeX in kvm_nonoise.txt")