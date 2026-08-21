from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.db import IntegrityError
from django.utils.html import format_html

from .models import User, Student, Teacher, Device


class CustomUserAdmin(UserAdmin):
    # Add role and phone to the edit form
    fieldsets = UserAdmin.fieldsets + (
        ('Custom Fields', {
            'fields': ('role', 'phone')
        }),
    )

    # Add role and phone to the add user form
    add_fieldsets = UserAdmin.add_fieldsets + (
        ('Custom Fields', {
            'fields': ('role', 'phone')
        }),
    )

    # Show role in the users list
    list_display = ['username', 'first_name', 'last_name', 'role', 'email']


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    """
    Admin view for enrolled devices.

    Shows which physical device is bound to which student, and lets an
    admin enable/disable a device's binding without touching the DB
    directly. Disabling a device frees up that student to re-enroll a
    new one and frees up that physical device fingerprint to be bound
    to a different student (see the model's UniqueConstraints).
    """

    list_display = [
        'roll_number',
        'student_name',
        'department',
        'short_fingerprint',
        'registered_at',
        'status_badge',
    ]
    list_filter = ['is_active', 'student__department']
    search_fields = [
        'student__roll_number',
        'student__user__first_name',
        'student__user__last_name',
        'device_fingerprint',
    ]
    readonly_fields = ['public_key', 'device_fingerprint', 'registered_at']
    ordering = ['-registered_at']
    actions = ['enable_devices', 'disable_devices']

    # --- list_display helper columns ---

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
        return format_html(
            '<span style="color: {}; font-weight: 600;">{}</span>', color, label
        )

    # --- bulk actions ---

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
            except IntegrityError:
                # Student already has another active device, or this
                # fingerprint is already bound to a different active student.
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
        updated = queryset.filter(is_active=True).update(is_active=False)
        self.message_user(request, f"Disabled {updated} device(s).")


admin.site.register(User, CustomUserAdmin)
admin.site.register(Student)
admin.site.register(Teacher)