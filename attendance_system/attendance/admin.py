from django.contrib import admin
from .models import Class, Enrollment, Session, AttendanceRecord

admin.site.register(Class)
admin.site.register(Enrollment)
admin.site.register(Session)
admin.site.register(AttendanceRecord)