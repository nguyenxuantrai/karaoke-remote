# Giữ lại các cấu trúc cần thiết cho Firebase và các lớp dữ liệu hằng số
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Giữ lại các phản chiếu ánh xạ hằng số của Dart/Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# =========================================================================
# LỆNH THẦN THÁNH ÉP R8 BỎ QUA CÁC LỚP CHƯA CÀI ĐẶT CỦA GOOGLE PLAY STORE
# =========================================================================
-dontwarn com.google.android.play.core.**
# =========================================================================
