import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:app_preguntas/controller.dart';
import 'package:permission_handler/permission_handler.dart';

class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  QuizPageState createState() => QuizPageState();
}

class QuizPageState extends State<QuizPage> {
  final QuizController controller = Get.put(QuizController());
  String headerText = "BLITO PREGUNTA";

  // Colores principales
  final Color teamAColor = const Color(0xFFFA9401);
  final Color teamBColor = const Color(0xFF346B80);
  final Color neutralColor = const Color(0xFFFFD85F);
  final Color progressBarColor = const Color(0xFF00E676);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await requestPermissions(); // Solicitar permisos
      await controller.loadQuestions(); // Cargar preguntas
    } catch (e) {
      log("Error en la inicialización: $e");
      Get.snackbar("Error", "No se pudo inicializar la aplicación.");
    }
  }

  Future<void> requestPermissions() async {
    try {
      final status = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      if (status[Permission.bluetooth]!.isGranted &&
          status[Permission.bluetoothScan]!.isGranted &&
          status[Permission.bluetoothConnect]!.isGranted) {
        log("Permisos de Bluetooth concedidos.");
      } else {
        log("Permisos faltantes.");
        Get.snackbar("Permisos", "Se requieren permisos de Bluetooth.");
      }
    } catch (e) {
      log("Error al solicitar permisos: $e");
      Get.snackbar("Error", "Error al solicitar permisos.");
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  /// Método para manejar las respuestas del usuario
  void checkAnswer(String answer) async {
    if (!controller.isConnected.value) {
      showWarning("Debe conectarse a un dispositivo Bluetooth.");
      return;
    }

    controller.isPaused.value = true; // Pausar el juego
    showWaitingForArduino(); // Mostrar modal de espera

    // Enviar la respuesta al Arduino y esperar la respuesta
    final isCorrect = await controller.sendDataToArduinoAndValidate(answer);

    // Actualizar puntaje y mostrar el resultado
    Navigator.pop(context); // Cerrar el modal de espera
    showResultModal(isCorrect);

    // Avanzar a la siguiente pregunta
    controller.nextQuestion(onGameFinished: showFinalResults);
    controller.isPaused.value = false; // Reanudar el juego
  }

  void showWarning(String message) {
    Get.snackbar(
      "Advertencia",
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.red,
      colorText: Colors.white,
      margin: const EdgeInsets.all(10),
    );
  }

  /// Mostrar modal de espera mientras se valida con Arduino
  void showWaitingForArduino() {
    Get.defaultDialog(
      barrierDismissible: false,
      title: "Esperando respuesta",
      middleText: "Esperando validación del Arduino...",
    );
  }

  /// Mostrar modal de resultado (Correcto o Incorrecto)
  void showResultModal(bool isCorrect) {
    Get.defaultDialog(
      title: isCorrect ? "¡Correcto!" : "Incorrecto",
      middleText: isCorrect
          ? "La respuesta es correcta. ¡Buen trabajo!"
          : "La respuesta es incorrecta. Inténtalo nuevamente.",
      textConfirm: "Continuar",
      onConfirm: () => Get.back(),
    );
  }

  /// Mostrar resultados finales al terminar el juego
  void showFinalResults() {
    Get.defaultDialog(
      title: "Resultados Finales",
      middleText:
          "Equipo A: ${controller.scoreA.value} puntos\nEquipo B: ${controller.scoreB.value} puntos",
      textConfirm: "Reiniciar Juego",
      onConfirm: () {
        controller.resetGame();
        Get.back();
      },
    );
  }

  /// Mostrar dispositivos Bluetooth disponibles
  Future<void> showBluetoothDevices(BuildContext context) async {
    controller.startDiscovery();

    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Obx(() {
          if (controller.isScanning.value) {
            return const Center(child: CircularProgressIndicator());
          }

          if (controller.discoveredDevices.isEmpty) {
            return const Center(
              child: Text(
                "No se encontraron dispositivos cercanos.\nAsegúrese de que Bluetooth esté activado.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: controller.discoveredDevices.length,
            itemBuilder: (context, index) {
              final device = controller.discoveredDevices[index].device;

              return ListTile(
                title: Text(device.name ?? "Dispositivo sin nombre"),
                subtitle: Text(device.address),
                leading: const Icon(Icons.bluetooth),
                onTap: () async {
                  controller.isScanning.value = false;
                  Navigator.pop(context);

                  await connectToDevice(device.address);
                },
              );
            },
          );
        });
      },
    );
  }

  /// Método para conectar a un dispositivo Bluetooth seleccionado
  Future<void> connectToDevice(String address) async {
    try {
      controller.connectToHC05(address);
      if (controller.isConnected.value) {
        Get.snackbar(
          "Conexión exitosa",
          "Se conectó correctamente al dispositivo.",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        throw Exception("La conexión no se pudo establecer.");
      }
    } catch (e) {
      log("Error al conectar: $e");
      Get.snackbar(
        "Error de conexión",
        "No se pudo conectar al dispositivo. Verifique que esté encendido y accesible.",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isQuestionsLoaded.value) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      final question =
          controller.questions[controller.currentQuestionIndex.value];
      final optionLabels = ['a', 'b', 'c', 'd'];
      Color activeColor = controller.isPaused.value
          ? neutralColor
          : (controller.currentTeam.value == "A" ? teamAColor : teamBColor);

      return Scaffold(
        body: Column(
          children: [
            ClipPath(
              clipper: HeaderClipper(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(color: activeColor),
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        headerText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: -4,
                      child: IconButton(
                        onPressed: () => showBluetoothDevices(context),
                        icon: Icon(
                          Icons.bluetooth,
                          color: controller.isConnected.value
                              ? Colors.blue
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: activeColor, width: 2),
                      ),
                      child: Text(
                        question["question"],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 15),
                    ...question["options"].asMap().entries.map<Widget>((entry) {
                      int index = entry.key;
                      String option = entry.value;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: ElevatedButton(
                          onPressed: controller.isPaused.value
                              ? null
                              : () => checkAnswer(option),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              side: BorderSide(color: activeColor),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 10),
                              CircleAvatar(
                                backgroundColor: activeColor,
                                child: Text(
                                  optionLabels[index],
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option,
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 10),
                    Text(
                      "Tiempo restante: ${controller.timeLeft.value} segundos",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: LinearProgressIndicator(
                        value: controller.timeLeft.value / 15,
                        minHeight: 10,
                        backgroundColor: Colors.grey.shade300,
                        color: progressBarColor,
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ElevatedButton(
                        onPressed: controller.togglePause,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30.0),
                            side: BorderSide(color: neutralColor),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: neutralColor,
                              child: Icon(
                                controller.isPaused.value
                                    ? Icons.play_arrow
                                    : Icons.pause,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              controller.isPaused.value
                                  ? "Iniciar Juego"
                                  : "Pausa",
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
        size.width / 2, size.height, size.width, size.height - 40);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
  }
}
