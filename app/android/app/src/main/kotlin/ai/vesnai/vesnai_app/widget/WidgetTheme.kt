package ai.vesnai.vesnai_app.widget

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.sp
import androidx.glance.color.ColorProvider
import androidx.glance.text.FontWeight
import androidx.glance.text.TextStyle

private fun fixedColor(color: Color) = ColorProvider(day = color, night = color)

/** Material 3 light palette — mirrors [VesnaiWidgetPalette] in Flutter theme.dart. */
object VesnaiWidgetColors {
    val surface = Color(0xFFF5FBF5)
    val onSurface = Color(0xFF171D19)
    val onSurfaceVariant = Color(0xFF404943)
    val primary = Color(0xFF226A4C)
    val onPrimary = Color(0xFFFFFFFF)
    val primaryContainer = Color(0xFFAAF2CB)
    val onPrimaryContainer = Color(0xFF005236)
    val surfaceContainerLow = Color(0xFFF0F5EF)
    val generatedAccent = Color(0xFF8E6BD6)
    val generatedTint = Color(0x2E8E6BD6)

    // Sync with VesnaiTypePalette in app/lib/theme.dart
    val typeIdeaIcon = Color(0xFFC9920E)
    val typeIdeaFill = Color(0xFFF0D78C)
    val typeTaskIcon = Color(0xFF1F9689)
    val typeTaskFill = Color(0xFF8ED9CF)
    val typePhotoIcon = Color(0xFF7B52B8)
    val typePhotoFill = Color(0xFFD4C0EF)
}

object NoteTypeWidgetStyle {
    fun iconRes(type: String): Int = when (paletteBucket(type)) {
        "Idea" -> ai.vesnai.vesnai_app.R.drawable.ic_note_type_idea
        "Task" -> ai.vesnai.vesnai_app.R.drawable.ic_note_type_task
        "Photo" -> ai.vesnai.vesnai_app.R.drawable.ic_note_type_photo
        else -> ai.vesnai.vesnai_app.R.drawable.ic_note_type_note
    }

    fun color(type: String): Color = when (paletteBucket(type)) {
        "Idea" -> VesnaiWidgetColors.typeIdeaIcon
        "Task" -> VesnaiWidgetColors.typeTaskIcon
        "Photo" -> VesnaiWidgetColors.typePhotoIcon
        else -> VesnaiWidgetColors.onPrimaryContainer
    }

    fun tint(type: String): Color = when (paletteBucket(type)) {
        "Idea" -> VesnaiWidgetColors.typeIdeaFill
        "Task" -> VesnaiWidgetColors.typeTaskFill
        "Photo" -> VesnaiWidgetColors.typePhotoFill
        else -> VesnaiWidgetColors.primaryContainer
    }

    fun colorProvider(type: String) = fixedColor(color(type))

    private fun paletteBucket(type: String): String = when (type.trim()) {
        "Idea", "Task", "Photo", "Note" -> type.trim()
        "Research" -> "Idea"
        "GeneratedImage", "GeneratedCaption" -> "Photo"
        "Memory" -> "Task"
        else -> "Note"
    }
}

object VesnaiWidgetTheme {
    val masthead = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onSurface),
        fontWeight = FontWeight.Bold,
        fontSize = 16.sp,
    )

    val tabActive = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onPrimaryContainer),
        fontWeight = FontWeight.Bold,
        fontSize = 12.sp,
    )

    val tabInactive = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onSurface),
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
    )

    val rowTitle = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onSurface),
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
    )

    val rowMeta = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onSurfaceVariant),
        fontSize = 11.sp,
    )

    val emptyState = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onSurfaceVariant),
        fontSize = 13.sp,
    )

    val aiLabel = TextStyle(
        color = fixedColor(VesnaiWidgetColors.generatedAccent),
        fontWeight = FontWeight.Bold,
        fontSize = 10.sp,
    )

    val rowIcon = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onPrimaryContainer),
        fontSize = 14.sp,
    )

    val addButton = TextStyle(
        color = fixedColor(VesnaiWidgetColors.onPrimary),
        fontWeight = FontWeight.Bold,
        fontSize = 18.sp,
    )
}
