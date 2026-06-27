import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

filename = Path(r"C:\Users\ritam\Desktop\Xen-vs-KVM\KVM\tests\RT-RT\result_1.txt")

data = np.genfromtxt(filename, comments='#')

latencies = data[:, 0]
frequencies = data[:, 1]

cdf = np.cumsum(frequencies) / np.sum(frequencies)

plt.figure(figsize=(8, 5))
plt.plot(latencies, cdf, marker='*', linestyle='-', color='b')

plt.xlabel(r'Latenza ($\mu s$)')
plt.ylabel('Cumulative Distribution Function (CDF)')
plt.title('CDF of latency')
plt.grid(True, linestyle='--', alpha=0.7)

plt.xlim(left=0, right=max(latencies))
plt.ylim(0, 1.05)

plt.show()

np.savetxt(
    "cdf_data.txt",
    np.column_stack((latencies, cdf)),
    fmt="%.0f %.6f",
    header="latency cdf",
    comments=""
)

print("Dati CDF esportati")