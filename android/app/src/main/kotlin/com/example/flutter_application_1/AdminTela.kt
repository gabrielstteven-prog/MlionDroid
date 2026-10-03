package com.example.flutter_application_1

import android.app.admin.DeviceAdminReceiver

/**
 * "Administrador do dispositivo" com uma única permissão: apagar a tela
 * (force-lock). É o único jeito de um app desligar a tela na hora, sem
 * depender do tempo de espera do sistema. O usuário ativa uma vez em
 * Configurações > Modo Noite.
 */
class AdminTela : DeviceAdminReceiver()
