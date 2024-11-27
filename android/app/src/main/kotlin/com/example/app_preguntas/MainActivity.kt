package com.example.app_preguntas

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.bluetooth"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Verificar que flutterEngine no sea nulo
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger != null) {
            // Configurar el canal de comunicación entre Flutter y Android
            MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableBluetooth" -> handleEnableBluetooth(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Manejar la activación de Bluetooth.
     * @param result Resultado que se envía de vuelta a Flutter
     */
    private fun handleEnableBluetooth(result: MethodChannel.Result) {
        val bluetoothAdapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()

        if (bluetoothAdapter == null) {
            // Si el dispositivo no soporta Bluetooth
            result.error("UNAVAILABLE", "Bluetooth no está disponible en este dispositivo.", null)
            return
        }

        if (bluetoothAdapter.isEnabled) {
            // Si Bluetooth ya está activado
            result.success("Bluetooth ya está activado.")
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Para Android 13+ (API 33), abrir configuración para activar Bluetooth manualmente
                promptUserToEnableBluetooth(result)
            } else {
                // Para versiones anteriores, activar Bluetooth automáticamente
                val success = bluetoothAdapter.enable()
                if (success) {
                    result.success("Bluetooth activado correctamente.")
                } else {
                    result.error("ERROR", "No se pudo activar Bluetooth automáticamente.", null)
                }
            }
        }
    }

    /**
     * Abrir la configuración de Bluetooth para que el usuario lo active manualmente (Android 13+).
     * @param result Resultado que se envía de vuelta a Flutter
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun promptUserToEnableBluetooth(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            startActivity(intent)
            result.success("Por favor, activa Bluetooth manualmente.")
        } catch (e: Exception) {
            result.error("ERROR", "No se pudo abrir la configuración de Bluetooth.", null)
        }
    }
}
