# Learned Lessons

Registre aqui aprendizados reais para evitar repeticao de erros.

## Formato

### Problema

### Causa

### Solucao aplicada

### Regra preventiva

### Quando consultar

## Aprendizados iniciais

### Problema

Scripts operacionais foram criados em `PowerShell` mesmo com foco em `Ubuntu/Linux`.

### Causa

A interface operacional nao foi alinhada ao sistema-alvo logo no inicio.

### Solucao aplicada

Substituir scripts `.ps1` por `.sh` e padronizar operacao em `bash`.

### Regra preventiva

Se o ambiente operacional for Linux, a interface de automacao deve ser Linux-first, salvo exigencia explicita contraria.

### Quando consultar

Ao criar ou revisar scripts operacionais.

### Problema

Erros de quoting em comandos encadeados aumentam retrabalho e desperdicam chamadas.

### Causa

Execucao indireta entre shells diferentes sem simplificacao do comando.

### Solucao aplicada

Preferir comandos curtos, scriptados e com menos camadas de quoting.

### Regra preventiva

Se um comando com quoting complexo puder ser simplificado, documente e use a forma mais curta e previsivel.

### Quando consultar

Ao validar scripts ou chamar ferramentas a partir de outro shell.
