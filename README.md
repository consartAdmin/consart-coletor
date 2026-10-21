# CONSART Coletor — Inventário Mobile

App Flutter (Android e iOS) do módulo `backend/public/inventoryMobile` do ERP.
Usa as mesmas APIs do módulo web:

| Função | Endpoint |
|---|---|
| Login | `POST /api/login` |
| Inventários abertos / criar de hoje | `GET/POST /api/inventories` |
| Buscar produto (barcode ou SKU) | `GET /api/products-mobile/search/:code` |
| Localizações / ler `LOC-...` | `GET /api/products-mobile/locations/options`, `/locations/barcode/:barcode` |
| Gravar localização do produto | `PUT /api/products-mobile/:product_code/location` |
| Criar lote | `POST /api/productsStockLots` |
| Salvar contagem | `POST /api/inventories/:id/items` |

## Rodar

```bash
flutter pub get
flutter run            # celular conectado por USB ou emulador
flutter build apk      # gera build/app/outputs/flutter-apk/app-release.apk
```

No primeiro acesso informe o endereço do servidor (ex.: `http://192.168.0.10:8080`
na rede local, ou a URL do Cloud Run). Emulador Android: `http://10.0.2.2:8080`.

## Fluxo

1. Login → escolhe (ou cria) o inventário do dia.
2. Lê o código do produto pela câmera ou por leitor físico (o campo de busca recebe o "Enter" do coletor).
3. Na contagem: lê a localização `LOC-...`, escolhe unidade e lote, digita a quantidade e salva.
4. Com "Abrir câmera após salvar" ligado, a câmera reabre para o próximo item.

## iPhone (TestFlight)

`.github/workflows/ios-testflight.yml` compila o app num Mac do GitHub Actions,
assina e envia para o TestFlight. Precisa destes secrets no repositório:
`APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_IDENTIFIER`,
`APP_STORE_CONNECT_PRIVATE_KEY` (conteúdo do arquivo `.p8`) e
`CERTIFICATE_PRIVATE_KEY` (chave RSA usada no certificado de distribuição).
Sem eles o workflow só compila, sem assinar.
