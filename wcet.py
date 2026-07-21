import pandas as pd

# 1. Sostituisci questi numeri con i tuoi valori reali di WCET
dati = {
    'NRT-NRT': [602, 44409, 2024],
    'NRT-RT':  [6114, 51069, 2299],
    'RT-NRT':  [93, 50257, 1502],
    'RT-RT':   [81, 9829, 1935]
}

# 2. Definisci i nomi delle righe
righe = ['BASELINE', 'STRESSHOST', 'STRESSHOST ISOLATED']

# 3. Crea la tabella (DataFrame)
tabella_wcet = pd.DataFrame(dati, index=righe)

print("Tabella WCET:\n")
print(tabella_wcet)

# Opzionale: decommenta queste righe per salvare la tabella su file
# tabella_wcet.to_csv('tabella_wcet.csv')
# tabella_wcet.to_excel('tabella_wcet.xlsx')