-- Plastinord — Supabase schema
-- Paste this whole file into Supabase Dashboard → SQL Editor → New Query → Run.
-- Safe to re-run: every CREATE uses IF NOT EXISTS and policies are dropped before re-creating.
--
-- Notes:
--   • IDs are TEXT because the app generates string IDs client-side (Date.now() + random).
--   • RLS (Row Level Security) is enabled with a permissive "allow anon all" policy on every
--     table. This matches the app's model: the only auth gate is the in-app SUPERVISORES code
--     (HUB / OWN / GUST2026). Anyone who can reach the URL can read/write — same as palamo.
--     If you later want stricter auth, swap these policies for ones that check JWT claims.
--   • Some columns hold JSON encoded strings (notas, descripcion, items, etapas, data) — the
--     app packs/unpacks these. Leaving them as text keeps things compatible.

-- =============================================================================
-- 1. registros — production records (per-stage entries)
-- =============================================================================
create table if not exists public.registros (
  id text primary key,
  etapa text,
  fecha date,
  maquina text,
  producto text,
  cliente text,
  supervisor_codigo text,
  supervisor_nombre text,
  empleado text,
  turno text,
  ldpe numeric,
  mlldpe numeric,
  pelicula numeric,
  desperdicio numeric,
  rollos_producidos numeric,
  lbs_impresion numeric,
  desperdicio_impresion numeric,
  lbs_corte_rollo numeric,
  desperdicio_corte_rollo numeric,
  ancho_rollo numeric,
  lbs_cortadora numeric,
  bolsas_producidas numeric,
  desperdicio_corte numeric,
  desperdicio_reciclado numeric,
  material_recuperado numeric,
  motivo_parada text,
  piezas_necesarias text,
  piezas_cambiadas text,
  duracion_parada numeric,
  notas text,
  created_at timestamptz default now()
);
create index if not exists registros_created_at_idx on public.registros (created_at desc);
create index if not exists registros_fecha_idx on public.registros (fecha desc);

-- =============================================================================
-- 2. resina_batches — resin mixing
-- =============================================================================
create table if not exists public.resina_batches (
  id text primary key,
  fecha date,
  ldpe numeric default 0,
  mlldpe numeric default 0,
  total numeric default 0,
  lote text,
  supervisor_nombre text,
  empleado text,
  turno text,
  notas text,
  created_at timestamptz default now()
);
create index if not exists resina_batches_created_at_idx on public.resina_batches (created_at desc);

-- =============================================================================
-- 3. ordenes — customer orders
-- =============================================================================
create table if not exists public.ordenes (
  id text primary key,
  cliente text,
  fecha_envio date,
  puerto text,
  notas text,        -- packed JSON: {_notas, _envios}
  items text,        -- JSON-stringified array of line items
  etapa text,
  creado_por text,
  creado_en text,
  created_at timestamptz default now()
);
create index if not exists ordenes_created_at_idx on public.ordenes (created_at desc);
create index if not exists ordenes_etapa_idx on public.ordenes (etapa);

-- =============================================================================
-- 4. producto_terminado — finished product inventory log
-- =============================================================================
create table if not exists public.producto_terminado (
  id text primary key,
  producto text,
  cantidad numeric,
  unidad text,
  tipo text,         -- 'entrada' | 'salida' | 'ajuste'
  destino text,
  orden_id text,
  fecha date,
  notas text,
  supervisor text,
  created_at timestamptz default now()
);
create index if not exists producto_terminado_created_at_idx on public.producto_terminado (created_at desc);
create index if not exists producto_terminado_producto_idx on public.producto_terminado (producto);

-- =============================================================================
-- 5. inventario_movimientos — raw material movements
-- =============================================================================
create table if not exists public.inventario_movimientos (
  id text primary key,
  tipo text,           -- 'entrada' | 'salida' | 'ajuste'
  material_id text,
  material_nombre text,
  cantidad numeric,
  unidad text,
  proveedor text,
  maquina text,
  notas text,
  fecha date,
  supervisor text,
  created_at timestamptz default now()
);
create index if not exists inventario_movimientos_created_at_idx on public.inventario_movimientos (created_at desc);

-- =============================================================================
-- 6. facturas — invoices (header)
-- =============================================================================
create table if not exists public.facturas (
  id text primary key,
  numero text,
  fecha date,
  cliente text,
  ncf text,           -- repurposed as NIF (Haitian tax id) — column kept named ncf for code compat
  moneda text default 'HTG',
  orden_id text,
  subtotal numeric default 0,
  impuesto numeric default 0,
  total numeric default 0,
  estado text default 'pendiente',  -- 'pendiente' | 'pagada'
  notas text,
  creado_por text,
  created_at timestamptz default now()
);
create index if not exists facturas_created_at_idx on public.facturas (created_at desc);
create index if not exists facturas_estado_idx on public.facturas (estado);

-- =============================================================================
-- 7. factura_items — invoice line items
-- =============================================================================
create table if not exists public.factura_items (
  id text primary key,
  factura_id text,
  producto text,
  cantidad numeric,
  precio_unitario numeric,
  subtotal numeric
);
create index if not exists factura_items_factura_id_idx on public.factura_items (factura_id);

-- =============================================================================
-- 8. cuentas_pagar — accounts payable
-- =============================================================================
create table if not exists public.cuentas_pagar (
  id text primary key,
  proveedor text,
  concepto text,
  monto numeric,
  moneda text default 'HTG',
  fecha_factura date,
  fecha_vencimiento date,
  estado text default 'pendiente',
  pagado numeric default 0,
  notas text,           -- packed JSON: {_notas, _cat}
  imagen text,
  creado_por text,
  created_at timestamptz default now()
);
create index if not exists cuentas_pagar_created_at_idx on public.cuentas_pagar (created_at desc);
create index if not exists cuentas_pagar_estado_idx on public.cuentas_pagar (estado);

-- =============================================================================
-- 9. gastos — direct expenses
-- =============================================================================
create table if not exists public.gastos (
  id text primary key,
  fecha date,
  categoria text,
  monto numeric,
  descripcion text,     -- packed JSON: {_desc, _moneda}
  proveedor text,
  creado_por text,
  created_at timestamptz default now()
);
create index if not exists gastos_created_at_idx on public.gastos (created_at desc);
create index if not exists gastos_categoria_idx on public.gastos (categoria);

-- =============================================================================
-- 10. pagos — payment records (against facturas / cuentas_pagar)
-- =============================================================================
create table if not exists public.pagos (
  id text primary key,
  factura_id text,
  cuenta_pagar_id text,
  monto numeric,
  moneda text default 'HTG',
  metodo text,          -- 'efectivo' | 'transferencia' | 'cheque'
  fecha date,
  notas text,
  creado_por text,
  created_at timestamptz default now()
);
create index if not exists pagos_created_at_idx on public.pagos (created_at desc);
create index if not exists pagos_factura_id_idx on public.pagos (factura_id);

-- =============================================================================
-- 11. nominas — processed payroll snapshots
-- =============================================================================
create table if not exists public.nominas (
  id text primary key,
  periodo text,
  label text,
  fecha timestamptz,
  procesado_por text,
  data text,                    -- full payroll snapshot as JSON
  total_nomina numeric default 0,
  total_adicional numeric default 0,
  total_otros numeric default 0,
  grand_total numeric default 0,
  created_at timestamptz default now()
);
create index if not exists nominas_created_at_idx on public.nominas (created_at desc);

-- =============================================================================
-- 12. lotes — production lots (Mezcla → Extrusión → Calibración → Corte → Empaque)
-- =============================================================================
create table if not exists public.lotes (
  id text primary key,
  numero text,
  fecha date,
  creado_por text,
  etapas text,                  -- JSON-stringified per-stage entries
  created_at timestamptz default now()
);
create index if not exists lotes_created_at_idx on public.lotes (created_at desc);

-- =============================================================================
-- 13. clientes — customer directory
-- =============================================================================
create table if not exists public.clientes (
  id text primary key,
  nombre text,
  telefono text,
  email text,
  direccion text,
  notas text,
  created_at timestamptz default now()
);
create index if not exists clientes_nombre_idx on public.clientes (nombre);

-- =============================================================================
-- 14. proveedores — supplier directory
-- =============================================================================
create table if not exists public.proveedores (
  id text primary key,
  nombre text,
  categoria text,
  telefono text,
  rnc text,                     -- repurposed as NIF (Haitian tax id) — column kept named rnc
  notas text,
  created_at timestamptz default now()
);
create index if not exists proveedores_nombre_idx on public.proveedores (nombre);

-- =============================================================================
-- 15. audit_log — change tracking
-- =============================================================================
create table if not exists public.audit_log (
  id text primary key,
  action text,                  -- 'create' | 'update' | 'delete'
  table_name text,
  record_id text,
  supervisor text,
  created_at timestamptz default now()
);
create index if not exists audit_log_created_at_idx on public.audit_log (created_at desc);
create index if not exists audit_log_table_idx on public.audit_log (table_name);

-- =============================================================================
-- Row Level Security: enable on every table, add permissive policies for anon
-- =============================================================================
do $$
declare t text;
begin
  for t in select unnest(array[
    'registros','resina_batches','ordenes','producto_terminado','inventario_movimientos',
    'facturas','factura_items','cuentas_pagar','gastos','pagos',
    'nominas','lotes','clientes','proveedores','audit_log'
  ]) loop
    execute format('alter table public.%I enable row level security;', t);
    execute format('drop policy if exists "anon_all_%s" on public.%I;', t, t);
    execute format(
      'create policy "anon_all_%s" on public.%I for all to anon using (true) with check (true);',
      t, t
    );
  end loop;
end $$;

-- =============================================================================
-- Done. Sanity check: list created tables.
-- =============================================================================
select tablename from pg_tables where schemaname = 'public' order by tablename;
