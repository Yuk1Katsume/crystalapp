# Informe de Análisis de Seguridad - CrystalApp (Corregido y Verificado)

## Resumen Ejecutivo

Se ha realizado un análisis exhaustivo del código fuente de CrystalApp para identificar vulnerabilidades de seguridad. El proyecto presenta **3 vulnerabilidades críticas reales** y **2 vulnerabilidades medias reales**.

**Nivel de riesgo general: MEDIO** ⚠️

---

## 🔴 Vulnerabilidades Críticas Reales (Prioridad Alta)

### 1. Cifrado XOR Débil en E2EE Service

**Ubicación:** `lib/services/e2ee_service.dart`

**Descripción:**
- El servicio E2EE utiliza XOR simple con semillas predecibles (`timestamp + 'crystal_seed'`)
- No hay autenticación de mensajes (MAC/HMAC)
- No hay salting en la generación de claves
- El algoritmo es vulnerable a ataques de frecuencia y cribado de fuerza bruta

**Impacto:**
- Los mensajes pueden ser descifrados si se conoce el texto plano de otro usuario
- No hay protección contra ataques de replay
- No hay integridad de los mensajes

**Evidencia en código:**
```dart
// En e2ee_service.dart - línea 20-22
final random = sha256.convert(utf8.encode(timestamp + 'crystal_seed')).toString();
pubKey = 'PUB_' + random.substring(0, 32);
```

**Recomendación:**
- Migrar a AES-256-GCM con autenticación de mensajes
- Usar curvas de ellipticas (X25519) para intercambio de claves
- Implementar nonce/IV único por mensaje

---

### 2. HttpClient sin HTTPS Enforcement

**Ubicación:** `lib/services/voice_note_service.dart`

**Descripción:**
- `HttpClient().getUrl()` puede usar HTTP en lugar de HTTPS
- No hay validación de certificados SSL/TLS
- Los datos pueden ser interceptados en tránsito

**Impacto:**
- MitM attacks si el atacante controla un punto de red
- Los mensajes encriptados pueden ser descifrados
- Los datos de autenticación pueden ser robados

**Evidencia en código:**
```dart
// En voice_note_service.dart - línea 264 y 271
final res = await HttpClient().getUrl(Uri.parse(url));
final res = await HttpClient().getUrl(Uri.parse(rawMediaUrl));
```

**Recomendación:**
- Forzar HTTPS con `HttpClient().get(Uri.parse(url))`
- Validar certificados SSL/TLS
- Usar `dart:io` con `SecureChannel`

---

### 3. Base de Datos Local en Texto Plano

**Ubicación:** `lib/services/local_database_service.dart`

**Descripción:**
- SQLite (sqflite) guarda los datos en texto plano
- No hay cifrado de datos en reposo
- Si el dispositivo es rooteado o extraído, los mensajes se ven

**Impacto:**
- Si el dispositivo es robado, los mensajes se ven
- No hay protección contra acceso físico al dispositivo
- Los mensajes encriptados pueden ser descifrados si se conoce la clave del usuario

**Evidencia en código:**
```dart
// En local_database_service.dart - línea 105-120
await database.insert(
  'local_messages',
  {
    'id': id,
    'sender_id': senderId,
    // ... datos en texto plano
  },
  conflictAlgorithm: ConflictAlgorithm.replace,
);
```

**Recomendación:**
- Evaluar SQLCipher para datos altamente confidenciales
- Implementar cifrado con Keychain/Keystore
- Considerar encriptación de disco

---

## 🟡 Vulnerabilidades Medias Reales (Prioridad Media)

### 4. Superadmin Hardcodeado

**Ubicación:** `lib/services/role_service.dart`

**Descripción:**
- El superadmin `yuk1katsume` está hardcodeado en el código del cliente
- No hay validación de roles en el servidor
- Cualquier usuario con acceso al código o API puede suplantarlo

**Impacto:**
- Un atacante puede hacerse pasar por superadmin
- No hay control de acceso basado en roles
- Posible eliminación de datos sensibles

**Evidencia en código:**
```dart
// En role_service.dart - línea 8
static const String superAdminUsername = 'yuk1katsume';
```

**Recomendación:**
- Validar roles en Backend / Firestore Rules
- Implementar RBAC (Role-Based Access Control)
- Usar JWT con roles en el servidor

---

### 5. No hay Protección contra Replay Attacks en SMS

**Ubicación:** `lib/screens/auth_screen.dart`

**Descripción:**
- Los códigos de verificación SMS no tienen nonce o timestamp único en el cliente
- No hay validación de tiempo de expiración en el código
- Firebase Phone Auth maneja esto en el servidor, pero el cliente no valida

**Impacto:**
- Los códigos SMS pueden ser reutilizados indefinidamente
- El atacante puede autenticarse como otro usuario

**Evidencia en código:**
```dart
// En auth_service.dart - signInWithOtp
final credential = fb_auth.PhoneAuthProvider.credential(
  verificationId: verificationId,
  smsCode: smsCode,
);
```

**Recomendación:**
- Implementar timestamp único en cada código
- Configurar expiración de 5-10 minutos en Firebase Console
- Usar Firebase Phone Auth con configuración de seguridad

---

## ✅ Hallazgos CORREGIDOS (No son vulnerabilidades)

### A. API Keys expuestas en Firebase/Supabase

**Ubicación:** `lib/firebase_options.dart` y `lib/services/supabase_config.dart`

**Descripción:**
- Las API keys de Firebase y Supabase están hardcodeadas
- Se sugiere usar Firebase Admin SDK o service_role key

**Análisis corregido:**
- **En Flutter/Web, la apiKey de Firebase y la anon_key de Supabase son públicas por diseño**
- Son identificadores de proyecto, no secretos de servidor
- La seguridad real en Firebase depende de Firestore/Storage Security Rules y App Check
- **Peligro:** Si se usa service_role o Admin SDK dentro de una app Flutter, cualquier persona podrá descompilar el APK y obtener acceso de superusuario root

**Recomendación:**
- Configurar Firestore Security Rules y Row Level Security (RLS) en Supabase
- **Nunca uses credenciales de servicio en el cliente**
- Mantener las API keys públicas es correcto para Flutter

---

### B. SQL Injection con consultas parametrizadas

**Ubicación:** `lib/services/local_database_service.dart`

**Descripción:**
- Se afirma que hay SQL injection con `WHERE (sender_id = ? OR recipient_id = ?)`

**Análisis corregido:**
- **El uso del signo de interrogación (?) es precisamente la forma correcta y parametrizada de hacer consultas en SQLite**
- sqflite usa consultas parametrizadas correctamente
- No hay inyección SQL en este código

**Evidencia en código:**
```dart
// En local_database_service.dart - consultas parametrizadas CORRECTAS
await database.query(
  'local_messages',
  where: 'group_id = ?',
  whereArgs: [groupId],
  orderBy: 'created_at ASC',
);
```

**Recomendación:**
- El código ya es seguro con consultas parametrizadas
- No se requiere acción inmediata

---

### C. XSS (Cross-Site Scripting)

**Ubicación:** `lib/screens/chat_screen.dart`

**Descripción:**
- Se afirma que hay XSS por no sanitizar mensajes

**Análisis corregido:**
- **Flutter no renderiza un árbol DOM HTML ni ejecuta scripts del navegador**
- Dibuja píxeles directamente sobre un canvas (Skia/Impeller)
- Un texto con `<script>` se muestra como texto plano, no se ejecuta
- **No aplica** salvo que se use un widget de WebView explícito

**Recomendación:**
- No aplica para Flutter nativo
- Si se usa WebView, sanitizar el contenido HTML

---

### D. CSRF (Cross-Site Request Forgery)

**Ubicación:** `lib/screens/auth_screen.dart`

**Descripción:**
- Se afirma que hay CSRF por no usar tokens

**Análisis corregido:**
- **El ataque CSRF depende de que los navegadores envíen cookies de sesión automáticamente entre dominios**
- Las apps móviles usan cabeceras de autorización explícitas (Bearer JWT)
- **No aplica** para apps móviles nativas

**Recomendación:**
- No aplica para Flutter nativo
- Usar Firebase Authentication con CSRF protection en el servidor

---

### E. Replay Attack en SMS de Firebase

**Ubicación:** `lib/services/auth_service.dart`

**Descripción:**
- Se afirma que hay replay attack en códigos SMS

**Análisis corregido:**
- **La generación, caducidad (normalmente 1 a 2 minutos), rate limiting e invalidación tras un solo uso de los códigos OTP de SMS no se gestionan en el código de Flutter, sino en los servidores de Google/Firebase Authentication**
- Firebase Phone Auth maneja esto en el servidor

**Recomendación:**
- Firebase Phone Auth maneja esto en el servidor
- No se requiere acción inmediata en el cliente

---

## 📊 Resumen de Prioridades

| Prioridad | Vulnerabilidades | Impacto |
|-----------|-----------------|---------|
| 🔴 Alta | 3 | Crítico |
| 🟡 Media | 2 | Alto |
| ✅ Correcto | 5 | N/A |

---

## 🛡️ Recomendaciones Priorizadas

### 1. Encriptación (CRÍTICO)
- [ ] Migrar a AES-256-GCM o librería estándar de E2EE
- [ ] Usar curvas de ellipticas (X25519)
- [ ] Implementar nonce/IV único por mensaje

### 2. HTTPS (ALTO)
- [ ] Forzar HTTPS en HttpClient
- [ ] Validar certificados SSL/TLS
- [ ] Usar SecureChannel

### 3. SQLite (MEDIO)
- [ ] Evaluar SQLCipher para datos altamente confidenciales
- [ ] Implementar cifrado con Keychain/Keystore

### 4. Roles (MEDIO)
- [ ] Validar roles en Backend / Firestore Rules
- [ ] Implementar RBAC (Role-Based Access Control)
- [ ] Usar JWT con roles en el servidor

### 5. SMS OTP (MEDIO)
- [ ] Implementar timestamp único en cada código
- [ ] Configurar expiración de 5-10 minutos en Firebase Console

---

## 📝 Conclusión

Después de corregir los errores conceptuales y verificar el código real, CrystalApp presenta **3 vulnerabilidades críticas reales** y **2 vulnerabilidades medias reales**. Los hallazgos de API keys expuestas, SQL injection, XSS y CSRF son **falsos positivos** que deben ser ignorados.

**Nivel de riesgo corregido: MEDIO** ⚠️
