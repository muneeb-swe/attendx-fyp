from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.db import IntegrityError
from django.utils.html import format_html

from .models import User, Student, Teacher, Device, DeviceEvent


class CustomUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (
        ('Custom Fields', {'fields': ('role', 'phone')}),
    )
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('Custom Fields', {'fields': ('role', 'phone')}),
    )
    list_display = ['username', 'first_name', 'last_name', 'role', 'email']


class DeviceEventInline(admin.TabularInline):
    """Shows this device's history directly on its own admin page."""
    model = DeviceEvent
    fk_name = 'device'
    extra = 0
    can_delete = False
    readonly_fields = ['event_type', 'device_fingerprint', 'performed_by',
                        'conflicting_student', 'notes', 'created_at']
    ordering = ['-created_at']

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    """
    Enrolled-devices view: which device belongs to which student,
    current status, and (via the inline above) its full history.

    Deliberately has NO delete action. AttendanceRecord.device uses
    on_delete=CASCADE, so hard-deleting a Device would silently
    delete every attendance record signed with it — destroying
    exactly the history this dashboard exists to show. "Removing"
    a device should always mean disabling it, never deleting the row.
    If you want deletion to be safe in future, first migrate
    AttendanceRecord.device to on_delete=SET_NULL.
    """

    list_display = [
        'roll_number', 'student_name', 'department',
        'short_fingerprint', 'registered_at', 'status_badge',
    ]
    list_filter = ['is_active', 'student__department']
    search_fields = [
        'student__roll_number', 'student__user__first_name',
        'student__user__last_name', 'device_fingerprint',
    ]
    readonly_fields = ['public_key', 'device_fingerprint', 'registered_at', 'is_active']
    ordering = ['-registered_at']
    actions = ['enable_devices', 'disable_devices']
    inlines = [DeviceEventInline]

    # is_active is deliberately in readonly_fields above: it must only
    # change via enable_devices/disable_devices (or the web dashboard's
    # device_toggle view), never by editing the field directly on this
    # form, so a DeviceEvent is always written and the audit log can't
    # be silently bypassed.

    def has_delete_permission(self, request, obj=None):
        # See class docstring — deletion is intentionally disabled.
        return False

    @admin.display(description='Roll Number', ordering='student__roll_number')
    def roll_number(self, obj):
        return obj.student.roll_number

    @admin.display(description='Student')
    def student_name(self, obj):
        return obj.student.user.get_full_name() or obj.student.user.username

    @admin.display(description='Department', ordering='student__department')
    def department(self, obj):
        return obj.student.department

    @admin.display(description='Device Fingerprint')
    def short_fingerprint(self, obj):
        fp = obj.device_fingerprint
        return fp if len(fp) <= 40 else f"{fp[:40]}…"

    @admin.display(description='Status', ordering='is_active')
    def status_badge(self, obj):
        color = '#1a7f37' if obj.is_active else '#999999'
        label = 'Active' if obj.is_active else 'Disabled'
        return format_html('<span style="color: {}; font-weight: 600;">{}</span>', color, label)

    @admin.action(description='Enable selected device(s)')
    def enable_devices(self, request, queryset):
        enabled, failed = 0, []
        for device in queryset:
            if device.is_active:
                continue
            device.is_active = True
            try:
                device.save()
                enabled += 1
                DeviceEvent.objects.create(
                    student=device.student,
                    device=device,
                    event_type='reactivated',
                    device_fingerprint=device.device_fingerprint,
                    performed_by=request.user,
                )
            except IntegrityError:
                failed.append(str(device))

        if enabled:
            self.message_user(request, f"Enabled {enabled} device(s).")
        if failed:
            self.message_user(
                request,
                "Could not enable (student or fingerprint already has an "
                "active device): " + ", ".join(failed),
                level='ERROR',
            )

    @admin.action(description='Disable selected device(s)')
    def disable_devices(self, request, queryset):
        updated = 0
        for device in queryset.filter(is_active=True):
            device.is_active = False
            device.save(update_fields=['is_active'])
            updated += 1
            DeviceEvent.objects.create(
                student=device.student,
                device=device,
                event_type='deactivated',
                device_fingerprint=device.device_fingerprint,
                performed_by=request.user,
            )
        self.message_user(request, f"Disabled {updated} device(s).")


@admin.register(DeviceEvent)
class DeviceEventAdmin(admin.ModelAdmin):
    """
    Read-only audit trail. This is the answer to 'which student
    changed their device, when, and what happened' — including
    mismatch attempts that never resulted in an actual Device row
    (e.g. someone tried to enroll a fingerprint that already
    belonged to another student).
    """

    list_display = [
        'created_at', 'event_type', 'student_roll', 'device_fingerprint',
        'conflicting_student_roll', 'performed_by',
    ]
    list_filter = ['event_type', 'created_at']
    search_fields = [
        'student__roll_number', 'device_fingerprint',
        'conflicting_student__roll_number',
    ]
    ordering = ['-created_at']

    def has_add_permission(self, request):
        return False

    def has_change_permission(self, request, obj=None):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    @admin.display(description='Student', ordering='student__roll_number')
    def student_roll(self, obj):
        return obj.student.roll_number

    @admin.display(description='Conflicting Student', ordering='conflicting_student__roll_number')
    def conflicting_student_roll(self, obj):
        return obj.conflicting_student.roll_number if obj.conflicting_student else '—'


admin.site.register(User, CustomUserAdmin)
admin.site.register(Student)
admin.site.register(Teacher)
