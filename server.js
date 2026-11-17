const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const PUBLIC = path.join(__dirname, 'public');

app.use(express.static(PUBLIC));
app.get(/.*/, (req, res) => res.sendFile(path.join(PUBLIC, 'index.html')));

app.listen(PORT, () => {
  console.log(`Conecta Dons frontend disponível em http://localhost:${PORT}`);
  console.log('Dados, autenticação e regras de negócio são tratados pelo Supabase.');
});
