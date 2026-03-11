from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
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


admin.site.register(User, CustomUserAdmin)
admin.site.register(Student)
admin.site.register(Teacher)
admin.site.register(Device)