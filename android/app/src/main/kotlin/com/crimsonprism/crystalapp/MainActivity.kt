package com.crimsonprism.crystalapp

import android.database.Cursor
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.crimsonprism.crystalapp/contacts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getContacts") {
                try {
                    val contactsList = mutableListOf<Map<String, String>>()
                    val cursor: Cursor? = contentResolver.query(
                        ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                        arrayOf(
                            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                            ContactsContract.CommonDataKinds.Phone.NUMBER
                        ),
                        null,
                        null,
                        ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
                    )

                    cursor?.use {
                        val nameIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
                        val numberIndex = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)

                        while (it.moveToNext()) {
                            val name = if (nameIndex >= 0) it.getString(nameIndex) ?: "" else ""
                            val number = if (numberIndex >= 0) it.getString(numberIndex) ?: "" else ""
                            if (number.isNotBlank()) {
                                contactsList.add(mapOf(
                                    "name" to name,
                                    "phone" to number
                                ))
                            }
                        }
                    }
                    result.success(contactsList)
                } catch (e: Exception) {
                    result.error("CONTACTS_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
