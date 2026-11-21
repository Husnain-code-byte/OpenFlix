package com.lagradost.cloudstream3.ui.settings

object Globals {
    const val PHONE = 1
    const val TV = 2
    const val EMULATOR = 4

    fun isLayout(flag: Int): Boolean = (flag and PHONE) != 0
}
