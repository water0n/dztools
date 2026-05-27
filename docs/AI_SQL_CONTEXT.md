# Contexto SQL para IA

Este documento define el contexto curado que dztools debe enviar a la IA cuando el usuario pide generar consultas SQL para bases NationalSoft/Sistema. No se debe enviar `DBSQL.dat` completo al modelo; este archivo es la referencia humana y `src/resources/ai-sql-context.json` es la version compacta usada por la app.

## Reglas generales

- Motor: SQL Server.
- Generar solo consultas `SELECT`.
- No generar ni sugerir `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `DROP`, `ALTER`, `TRUNCATE`, `EXEC`, `CREATE`, `BACKUP`, `RESTORE` ni procedimientos almacenados.
- Usar rangos de fecha semiabiertos: `>= inicio AND < fin`.
- Para ventas cerradas usar `dbo.cheques.cierre`.
- Para ventas operativas excluir canceladas con `dbo.cheques.cancelado = 0`.
- Para reportes por empresa usar `dbo.cheques.idempresa` o las vistas de reporte con `idempresa`.
- Si una pregunta pide "actuales" o "hoy", interpretar como el dia actual usando `CAST(GETDATE() AS date)`.
- Si una pregunta pide "ultimo mes", interpretar como mes calendario anterior.
- La IA debe devolver solo SQL, sin Markdown ni explicaciones, para que dztools pueda insertarlo en el editor.

## Dominio ventas

Fuente principal: `dbo.cheques`.

Vista recomendada para resumen diario: `dbo.vwrepventascheques`.

Columnas principales:

- `folio`: identificador de cuenta.
- `fecha`: apertura de la cuenta.
- `cierre`: fecha/hora de cierre de venta.
- `idcliente`: cliente asociado.
- `idempresa`: empresa/sucursal.
- `pagado`: cuenta pagada.
- `cancelado`: cuenta cancelada.
- `subtotal`: subtotal.
- `totalimpuesto1`: impuesto principal.
- `descuentoimporte`: descuento monetario.
- `total`: total de venta.
- `totalalimentos`, `totalbebidas`, `totalotros`: desglose operativo.
- `nopersonas`: trafico/clientes.

Consulta base para ventas de hoy:

```sql
SELECT
    CAST(ch.cierre AS date) AS fecha,
    ch.idempresa,
    COUNT(*) AS cuentas,
    SUM(ch.subtotal) AS subtotal,
    SUM(ch.totalimpuesto1) AS impuestos,
    SUM(ch.descuentoimporte) AS descuentos,
    SUM(ch.total) AS total
FROM dbo.cheques ch
WHERE ch.cancelado = 0
  AND ch.cierre >= CAST(GETDATE() AS date)
  AND ch.cierre < DATEADD(day, 1, CAST(GETDATE() AS date))
GROUP BY CAST(ch.cierre AS date), ch.idempresa
ORDER BY fecha DESC, ch.idempresa;
```

## Dominio clientes

Fuente principal: `dbo.clientes`.

Join principal:

```sql
dbo.cheques.idcliente = dbo.clientes.idcliente
```

Columnas utiles:

- `clientes.idcliente`: clave del cliente.
- `clientes.nombre`: nombre/razon del cliente.
- `clientes.rfc`: RFC.
- `clientes.fechaalta`: alta del cliente.
- `cheques.total`: importe vendido.
- `cheques.cierre`: fecha de venta cerrada.

Consulta base para clientes con mas ventas del ultimo mes:

```sql
SELECT TOP (20)
    c.idcliente,
    c.nombre,
    COUNT(*) AS cuentas,
    SUM(ch.total) AS total_ventas
FROM dbo.cheques ch
LEFT JOIN dbo.clientes c ON c.idcliente = ch.idcliente
WHERE ch.cancelado = 0
  AND ch.cierre >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 1, 0)
  AND ch.cierre < DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
GROUP BY c.idcliente, c.nombre
ORDER BY total_ventas DESC;
```

## Dominio productos

Tablas principales:

- `dbo.cheques`: cabecero de venta.
- `dbo.cheqdet`: detalle de productos.
- `dbo.productos`: catalogo de productos.

Joins principales:

```sql
dbo.cheques.folio = dbo.cheqdet.foliodet
dbo.cheqdet.idproducto = dbo.productos.idproducto
```

Vista recomendada:

- `dbo.vwrepproductosvendidoscheques`

Columnas utiles:

- `cheqdet.cantidad`: cantidad vendida.
- `cheqdet.precio`: precio en detalle.
- `cheqdet.descuento`: descuento del detalle.
- `productos.descripcion`: descripcion del producto.
- `productos.idgrupo`: grupo del producto.

Consulta base para productos mas vendidos:

```sql
SELECT TOP (20)
    p.idproducto,
    p.descripcion,
    SUM(cd.cantidad) AS cantidad,
    SUM(cd.cantidad * cd.precio) AS importe_estimado
FROM dbo.cheques ch
INNER JOIN dbo.cheqdet cd ON ch.folio = cd.foliodet
INNER JOIN dbo.productos p ON cd.idproducto = p.idproducto
WHERE ch.cancelado = 0
  AND ch.cierre >= DATEADD(month, DATEDIFF(month, 0, GETDATE()) - 1, 0)
  AND ch.cierre < DATEADD(month, DATEDIFF(month, 0, GETDATE()), 0)
GROUP BY p.idproducto, p.descripcion
ORDER BY cantidad DESC;
```

## Dominio pagos

Tablas principales:

- `dbo.cheques`
- `dbo.chequespagos`
- `dbo.formasdepago`

Joins principales:

```sql
dbo.chequespagos.folio = dbo.cheques.folio
dbo.chequespagos.idformadepago = dbo.formasdepago.idformadepago
```

Columnas utiles:

- `chequespagos.importe`: importe pagado.
- `chequespagos.propina`: propina pagada.
- `formasdepago.idformadepago`: clave de forma de pago.
- `formasdepago.descripcion`: descripcion si existe en la base destino.

Consulta base para ventas por forma de pago:

```sql
SELECT
    cp.idformadepago,
    COUNT(DISTINCT ch.folio) AS cuentas,
    SUM(cp.importe) AS importe,
    SUM(cp.propina) AS propina
FROM dbo.cheques ch
INNER JOIN dbo.chequespagos cp ON cp.folio = ch.folio
WHERE ch.cancelado = 0
  AND ch.cierre >= CAST(GETDATE() AS date)
  AND ch.cierre < DATEADD(day, 1, CAST(GETDATE() AS date))
GROUP BY cp.idformadepago
ORDER BY importe DESC;
```

## Dominio facturas

Usar para reportes fiscales o de facturacion, no como primera fuente de ventas operativas.

Tablas principales:

- `dbo.facturas`
- `dbo.facturasmovtos`
- `dbo.foliosfacturados`

Columnas utiles:

- `facturas.idfactura`: identificador.
- `facturas.serie`, `facturas.folio`: folio fiscal/serie.
- `facturas.fecha`: fecha de factura.
- `facturas.idcliente`: cliente fiscal.
- `facturas.cancelada`: factura cancelada.
- `facturas.subtotal`, `facturas.impuesto`, `facturas.total`: importes.

Regla:

- Para ventas operativas usar `cheques`.
- Para preguntas de facturas, CFDI, cancelaciones fiscales o timbrado usar `facturas`.

